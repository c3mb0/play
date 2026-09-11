//! Framed external-Port mechanism. Session policy stays in OTP.
use serde_json::{json, Value};
use std::{
    collections::VecDeque,
    fs::File,
    io::{self, Read, Write},
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::process::{CommandExt, ExitStatusExt},
    },
    process::{Command, Stdio},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
const LIMIT: usize = 1_048_576;

fn nonblock(fd: i32) -> io::Result<()> {
    let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
    if flags < 0 || unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) } < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}
fn temporary(e: &io::Error) -> bool {
    matches!(
        e.kind(),
        io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
    )
}
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
fn unhex(s: &str) -> Result<Vec<u8>> {
    if !s.len().is_multiple_of(2) || !s.is_ascii() {
        return Err("invalid hex".into());
    }
    (0..s.len())
        .step_by(2)
        .map(|i| Ok(u8::from_str_radix(&s[i..i + 2], 16)?))
        .collect()
}

#[derive(Default)]
struct Frames {
    input: Vec<u8>,
    output: VecDeque<u8>,
    eof: bool,
}
impl Frames {
    fn receive(&mut self) -> Result<Vec<Value>> {
        let mut b = [0; 8192];
        match io::stdin().read(&mut b) {
            Ok(0) => self.eof = true,
            Ok(n) => self.input.extend_from_slice(&b[..n]),
            Err(e) if temporary(&e) => {}
            Err(e) => return Err(e.into()),
        }
        let mut messages = Vec::new();
        while self.input.len() >= 4 {
            let n = u32::from_be_bytes(self.input[..4].try_into()?) as usize;
            if n == 0 || n > LIMIT {
                return Err("frame length outside 1..1048576".into());
            }
            if self.input.len() < n + 4 {
                break;
            }
            messages.push(serde_json::from_slice(&self.input[4..n + 4])?);
            self.input.drain(..n + 4);
        }
        if self.eof && !self.input.is_empty() {
            return Err("truncated frame".into());
        }
        Ok(messages)
    }
    fn send(&mut self, value: Value) -> Result<()> {
        let bytes = serde_json::to_vec(&value)?;
        if bytes.len() > LIMIT || self.output.len() + bytes.len() + 4 > LIMIT {
            return Err("outbound queue exceeds 1 MiB".into());
        }
        self.output.extend((bytes.len() as u32).to_be_bytes());
        self.output.extend(bytes);
        Ok(())
    }
    fn flush(&mut self) -> Result<()> {
        if !self.output.is_empty() {
            let bytes = self.output.make_contiguous();
            let written = unsafe { libc::write(1, bytes.as_ptr().cast(), bytes.len()) };
            let result = if written < 0 {
                Err(io::Error::last_os_error())
            } else {
                Ok(written as usize)
            };
            match result {
                Ok(0) => return Err("protocol stdout closed".into()),
                Ok(n) => {
                    self.output.drain(..n);
                }
                Err(e) if temporary(&e) => {}
                Err(e) => return Err(e.into()),
            }
        }
        Ok(())
    }
}

pub fn relay() -> Result<i32> {
    let mut guardian = Command::new(std::env::current_exe()?)
        .arg("--guardian")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()?;
    let mut input = guardian.stdin.take().ok_or("missing guardian stdin")?;
    // This process never forks after creating a thread. Guardian is single-threaded.
    std::thread::spawn(move || {
        let _ = io::copy(&mut io::stdin(), &mut input);
    });
    let mut output = unsafe { File::from_raw_fd(1) };
    let copy = io::copy(
        &mut guardian.stdout.take().ok_or("missing guardian stdout")?,
        &mut output,
    );
    // Returning exits the relay process, closing the guardian's command pipe even
    // when the input-forwarding thread is blocked. Never kill the cleanup owner.
    if copy.is_err() {
        return Ok(125);
    }
    let deadline = Instant::now() + Duration::from_secs(1);
    while Instant::now() < deadline {
        if let Some(status) = guardian.try_wait()? {
            return Ok(status.code().unwrap_or(125));
        }
        std::thread::sleep(Duration::from_millis(2));
    }
    Ok(125)
}

struct Subject {
    terminal_observation: Value,
    child: super::ChildOwner,
    input: Option<File>,
    readers: Vec<(String, File)>,
    pending: VecDeque<u8>,
    eof_requested: bool,
    pipe: bool,
    status: Option<std::process::ExitStatus>,
    interactive: bool,
    credit: usize,
    exit_reported: bool,
}

fn file<T: std::os::fd::IntoRawFd>(fd: T) -> File {
    unsafe { File::from_raw_fd(fd.into_raw_fd()) }
}
// Observe the configured slave before handing it to the child. No experiment policy.
fn terminal_observation(fd: i32) -> Result<Value> {
    let mut t: libc::termios = unsafe { std::mem::zeroed() };
    if unsafe { libc::tcgetattr(fd, &mut t) } < 0 {
        return Err(io::Error::last_os_error().into());
    }
    let mut w: libc::winsize = unsafe { std::mem::zeroed() };
    if unsafe { libc::ioctl(fd, libc::TIOCGWINSZ, &mut w) } < 0 {
        return Err(io::Error::last_os_error().into());
    }
    Ok(json!({"phase":"slave_before_spawn", "echo_mask":libc::ECHO,
        "canonical_mask":libc::ICANON,"vmin_index":libc::VMIN,"vtime_index":libc::VTIME,
        "configuration": {
            "termios": {"iflag":t.c_iflag,"oflag":t.c_oflag,"cflag":t.c_cflag,
                "lflag":t.c_lflag,"cc":t.c_cc.to_vec(),
                "ispeed":unsafe {libc::cfgetispeed(&t)},
                "ospeed":unsafe {libc::cfgetospeed(&t)},
                "canonical":t.c_lflag & libc::ICANON != 0,
                "echo":t.c_lflag & libc::ECHO != 0,"isig":t.c_lflag & libc::ISIG != 0},
            "dimensions":{"rows":w.ws_row,"cols":w.ws_col,
                "xpixel":w.ws_xpixel,"ypixel":w.ws_ypixel}}}))
}

fn spawn(spec: &Value) -> Result<Subject> {
    let mode = spec["attachment"].as_str().ok_or("missing attachment")?;
    if !["pipe", "slave", "ctty"].contains(&mode) {
        return Err("unknown attachment".into());
    }
    let executable = spec["executable"].as_str().ok_or("missing executable")?;
    let mut command = Command::new(executable);
    for arg in spec["argv"].as_array().ok_or("missing argv")? {
        command.arg(arg.as_str().ok_or("argv must contain strings")?);
    }
    command
        .env_clear()
        .current_dir(spec["cwd"].as_str().ok_or("missing cwd")?);
    for (key, value) in spec["environment"]
        .as_object()
        .ok_or("missing environment")?
    {
        command.env(
            key,
            value.as_str().ok_or("environment values must be strings")?,
        );
    }
    let mut master = None;
    let mut observed_terminal = Value::Null;
    if mode == "pipe" {
        command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
    } else {
        let t = &spec["terminal"]["termios"];
        let w = &spec["terminal"]["dimensions"];
        let mut term: libc::termios = unsafe { std::mem::zeroed() };
        if spec["interactive"] == true {
            term.c_iflag = libc::ICRNL | libc::IXON;
            term.c_oflag = libc::OPOST | libc::ONLCR;
            term.c_cflag = libc::CREAD | libc::CS8;
            term.c_lflag =
                libc::ISIG | libc::ICANON | libc::ECHO | libc::ECHOE | libc::ECHOK | libc::IEXTEN;
            for (index, value) in [
                (libc::VINTR, 3),
                (libc::VQUIT, 28),
                (libc::VERASE, 127),
                (libc::VKILL, 21),
                (libc::VEOF, 4),
                (libc::VSTART, 17),
                (libc::VSTOP, 19),
                (libc::VSUSP, 26),
                (libc::VMIN, 1),
                (libc::VTIME, 0),
            ] {
                term.c_cc[index] = value;
            }
            unsafe {
                libc::cfsetispeed(&mut term, libc::B38400);
                libc::cfsetospeed(&mut term, libc::B38400);
            }
        } else {
            term.c_iflag = super::native_number(t, "iflag")?;
            term.c_oflag = super::native_number(t, "oflag")?;
            term.c_cflag = super::native_number(t, "cflag")?;
            term.c_lflag = super::native_number(t, "lflag")?;
            let cc = t["cc"].as_array().ok_or("missing cc")?;
            if cc.len() != term.c_cc.len() {
                return Err("platform NCCS mismatch".into());
            }
            for (dst, src) in term.c_cc.iter_mut().zip(cc) {
                *dst = src.as_u64().ok_or("invalid cc")?.try_into()?;
            }
            if unsafe { libc::cfsetispeed(&mut term, super::native_number(t, "ispeed")?) } < 0 {
                return Err(io::Error::last_os_error().into());
            }
            if unsafe { libc::cfsetospeed(&mut term, super::native_number(t, "ospeed")?) } < 0 {
                return Err(io::Error::last_os_error().into());
            }
        }
        let mut win = libc::winsize {
            ws_row: super::native_number(w, "rows")?,
            ws_col: super::native_number(w, "cols")?,
            ws_xpixel: super::native_number(w, "xpixel")?,
            ws_ypixel: super::native_number(w, "ypixel")?,
        };
        let (mut m, mut s) = (-1, -1);
        if unsafe { libc::openpty(&mut m, &mut s, std::ptr::null_mut(), &mut term, &mut win) } < 0 {
            return Err(io::Error::last_os_error().into());
        }
        let master_file = unsafe { File::from_raw_fd(m) };
        let slave = unsafe { File::from_raw_fd(s) };
        for fd in [m, s] {
            if unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) } < 0 {
                return Err(io::Error::last_os_error().into());
            }
        }
        observed_terminal = terminal_observation(s)?;
        command
            .stdin(Stdio::from(slave.try_clone()?))
            .stdout(Stdio::from(slave.try_clone()?))
            .stderr(Stdio::from(slave));
        master = Some(master_file);
    }
    let controlling = mode == "ctty";
    unsafe {
        command.pre_exec(move || {
            if libc::setsid() < 0 {
                return Err(io::Error::last_os_error());
            }
            if controlling {
                if libc::ioctl(0, libc::TIOCSCTTY as _, 0) < 0 {
                    return Err(io::Error::last_os_error());
                }
                if libc::tcsetpgrp(0, libc::getpgrp()) < 0 {
                    return Err(io::Error::last_os_error());
                }
            }
            Ok(())
        });
    }
    let child = command.spawn();
    drop(command);
    let mut child = super::ChildOwner(child?);
    let (input, readers) = if let Some(master) = master {
        (
            Some(master.try_clone()?),
            vec![("pty_output".into(), master)],
        )
    } else {
        (
            Some(file(child.0.stdin.take().ok_or("missing stdin")?)),
            vec![
                (
                    "stdout".into(),
                    file(child.0.stdout.take().ok_or("missing stdout")?),
                ),
                (
                    "stderr".into(),
                    file(child.0.stderr.take().ok_or("missing stderr")?),
                ),
            ],
        )
    };
    for fd in input.iter().chain(readers.iter().map(|(_, f)| f)) {
        nonblock(fd.as_raw_fd())?;
    }
    Ok(Subject {
        terminal_observation: observed_terminal,
        child,
        input,
        readers,
        pending: VecDeque::new(),
        eof_requested: false,
        pipe: mode == "pipe",
        status: None,
        interactive: spec["interactive"] == true,
        credit: if spec["interactive"] == true {
            65536
        } else {
            usize::MAX
        },
        exit_reported: false,
    })
}

impl Drop for Subject {
    fn drop(&mut self) {
        if !self.interactive {
            return;
        }
        // Job control creates additional process groups within the owned PTY
        // session. Include background jobs, not just the current foreground job.
        let shell = self.child.0.id() as i32;
        let foreground = self
            .input
            .as_ref()
            .map(|f| unsafe { libc::tcgetpgrp(f.as_raw_fd()) })
            .unwrap_or(-1);
        let mut groups: Vec<i32> = [shell, foreground].into_iter().filter(|g| *g > 1).collect();
        match Command::new("/bin/ps").args(["-axo", "pid="]).output() {
            Ok(output) if output.status.success() => {
                for pid in String::from_utf8_lossy(&output.stdout)
                    .split_whitespace()
                    .filter_map(|s| s.parse::<i32>().ok())
                {
                    if unsafe { libc::getsid(pid) } == shell {
                        let group = unsafe { libc::getpgid(pid) };
                        if group > 1 {
                            groups.push(group);
                        }
                    }
                }
            }
            _ => eprintln!("PTY cleanup: could not enumerate owned session groups"),
        }
        groups.sort_unstable();
        groups.dedup();
        // This is teardown, not an invitation to handle HUP. No grace interval:
        // stopped jobs and jobs ignoring HUP/TERM must stop as well.
        for group in groups {
            unsafe {
                libc::kill(-group, libc::SIGKILL);
            }
        }
        self.input.take();
        self.readers.clear();
    }
}

struct Session {
    identity: Value,
    sequence: u64,
    started: Instant,
}
impl Session {
    fn emit(&mut self, frames: &mut Frames, event: &str, data: Value) -> Result<()> {
        self.sequence += 1;
        frames.send(json!({"v":1,"identity":self.identity,"seq":self.sequence,
            "unix_ns":SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos(),
            "monotonic_ns":self.started.elapsed().as_nanos(),"event":event,"data":data}))
    }
}

fn command(
    value: Value,
    subject: &mut Option<Subject>,
    session: &mut Session,
    frames: &mut Frames,
    last_command: &mut u64,
) -> Result<()> {
    if value["v"] != 1 {
        return Err("unsupported protocol version".into());
    }
    let sequence = value["seq"].as_u64().ok_or("missing command seq")?;
    if sequence != *last_command + 1 {
        return Err("nonconsecutive command sequence".into());
    }
    *last_command = sequence;
    if session.identity.is_null() {
        let identity = &value["identity"];
        for key in ["experiment", "cell", "session"] {
            if identity[key].as_str().is_none_or(str::is_empty) {
                return Err("invalid identity".into());
            }
        }
        session.identity = identity.clone();
    }
    if value["identity"] != session.identity {
        return Err("identity mismatch".into());
    }
    match value["command"].as_str().ok_or("missing command")? {
        "spawn" if subject.is_none() => {
            *subject = Some(spawn(&value["spec"])?);
            let s = subject.as_ref().ok_or("missing subject")?;
            session.emit(
                frames,
                "spawned",
                json!({"pid":s.child.0.id(),"guardian_pid":std::process::id(),
                "helper_pid":unsafe {libc::getppid()},"helper_version":env!("CARGO_PKG_VERSION"),
                "attachment":value["spec"]["attachment"],"new_session":true,
                "terminal_observation":s.terminal_observation}),
            )?;
        }
        "write" => {
            let s = subject.as_mut().ok_or("write before spawn")?;
            if s.input.is_none() || s.eof_requested {
                return Err("stdin closed".into());
            }
            let bytes = unhex(value["hex"].as_str().ok_or("missing hex")?)?;
            if s.pending.len() + bytes.len() > LIMIT {
                return Err("stdin queue exceeds 1 MiB".into());
            }
            s.pending.extend(bytes);
            session.emit(frames, "write_queued", json!({"command_seq":sequence}))?;
        }
        "credit" => {
            let s = subject.as_mut().ok_or("credit before spawn")?;
            let n = value["bytes"].as_u64().ok_or("invalid credit")? as usize;
            if !s.interactive || n == 0 || n > 65536 || s.credit + n > 65536 {
                return Err("credit outside output window".into());
            }
            s.credit += n;
        }
        "resize" => {
            let s = subject.as_mut().ok_or("resize before spawn")?;
            if s.pipe {
                return Err("resize requires PTY".into());
            }
            let rows: u16 = super::native_number(&value, "rows")?;
            let cols: u16 = super::native_number(&value, "cols")?;
            if !(1..=1000).contains(&rows) || !(2..=1000).contains(&cols) {
                return Err("invalid dimensions".into());
            }
            let fd = s.input.as_ref().ok_or("terminal closed")?.as_raw_fd();
            let win = libc::winsize {
                ws_row: rows,
                ws_col: cols,
                ws_xpixel: 0,
                ws_ypixel: 0,
            };
            if unsafe { libc::ioctl(fd, libc::TIOCSWINSZ, &win) } < 0 {
                return Err(io::Error::last_os_error().into());
            }
            let mut observed: libc::winsize = unsafe { std::mem::zeroed() };
            if unsafe { libc::ioctl(fd, libc::TIOCGWINSZ, &mut observed) } < 0 {
                return Err(io::Error::last_os_error().into());
            }
            session.emit(
                frames,
                "resized",
                json!({"rows":observed.ws_row,"cols":observed.ws_col,"command_seq":sequence}),
            )?;
        }
        "close" => {
            let s = subject.take().ok_or("close before spawn")?;
            drop(s);
            session.emit(
                frames,
                "closed",
                json!({"scope":"shell_and_foreground_groups","verified":false}),
            )?;
            frames.eof = true;
        }
        "close_stdin" => {
            let s = subject.as_mut().ok_or("close before spawn")?;
            if !s.pipe {
                return Err("PTY has no independent stdin half-close".into());
            }
            s.eof_requested = true;
        }
        "terminate" => {
            let s = subject.as_mut().ok_or("terminate before spawn")?;
            if s.status.is_none() {
                s.child.0.kill()?;
            }
            session.emit(
                frames,
                "signal_sent",
                json!({"signal":libc::SIGKILL,"command_seq":sequence}),
            )?;
        }
        "status" => {
            session.emit(frames, "status", json!({"spawned":subject.is_some()}))?;
        }
        _ => return Err("unsupported command or duplicate spawn".into()),
    }
    Ok(())
}

pub fn guardian() -> Result<i32> {
    nonblock(0)?;
    nonblock(1)?;
    let mut frames = Frames::default();
    let mut session = Session {
        identity: Value::Null,
        sequence: 0,
        started: Instant::now(),
    };
    let mut subject: Option<Subject> = None;
    let mut last_command = 0;
    let mut finishing = None;
    loop {
        if finishing.is_none() {
            let result: Result<()> = (|| {
                let incoming = frames.receive()?;
                // Loss of owner wins over buffered commands, including a spawn.
                if frames.eof {
                    return Ok(());
                }
                for value in incoming {
                    command(
                        value,
                        &mut subject,
                        &mut session,
                        &mut frames,
                        &mut last_command,
                    )?;
                }
                if let Some(s) = subject.as_mut() {
                    if let Some(input) = s.input.as_mut() {
                        if !s.pending.is_empty() {
                            let count = s.pending.len().min(4096);
                            match input.write(&s.pending.make_contiguous()[..count]) {
                                Ok(0) => return Err("subject stdin closed".into()),
                                Ok(n) => {
                                    let bytes: Vec<u8> = s.pending.drain(..n).collect();
                                    session.emit(
                                        &mut frames,
                                        "input_written",
                                        json!({"hex":hex(&bytes)}),
                                    )?;
                                }
                                Err(e) if temporary(&e) => {}
                                Err(e) => return Err(e.into()),
                            }
                        }
                    }
                    if s.eof_requested && s.pending.is_empty() && s.input.take().is_some() {
                        session.emit(&mut frames, "stdin_closed", json!({}))?;
                    }
                    let mut index = 0;
                    while index < s.readers.len() && s.credit > 0 && frames.output.len() < LIMIT / 2
                    {
                        let (name, reader) = &mut s.readers[index];
                        let mut bytes = [0; 4096];
                        let available = bytes.len().min(s.credit);
                        match reader.read(&mut bytes[..available]) {
                            Ok(0) => {
                                session.emit(&mut frames, "stream_end", json!({"stream":name}))?;
                                s.readers.remove(index);
                                continue;
                            }
                            Ok(n) => {
                                if s.interactive {
                                    s.credit -= n;
                                }
                                session.emit(&mut frames, name, json!({"hex":hex(&bytes[..n])}))?
                            }
                            Err(e) if temporary(&e) => {}
                            Err(e)
                                if cfg!(target_os = "linux")
                                    && e.raw_os_error() == Some(libc::EIO) =>
                            {
                                session.emit(
                                    &mut frames,
                                    "stream_end",
                                    json!({"stream":name,"errno":e.raw_os_error()}),
                                )?;
                                s.readers.remove(index);
                                continue;
                            }
                            Err(e) => return Err(e.into()),
                        }
                        index += 1;
                    }
                    if s.status.is_none() {
                        s.status = s.child.0.try_wait()?;
                    }
                    if let Some(status) = s.status {
                        if !s.exit_reported && (s.interactive || s.readers.is_empty()) {
                            s.exit_reported = true;
                            session.emit(
                                &mut frames,
                                "child_exit",
                                json!({"code":status.code(),"signal":status.signal()}),
                            )?;
                        }
                        if s.readers.is_empty() {
                            finishing = Some(Instant::now());
                        }
                    }
                }
                Ok(())
            })();
            if frames.eof {
                drop(subject);
                let until = Instant::now() + Duration::from_secs(1);
                while !frames.output.is_empty() && Instant::now() < until {
                    frames.flush()?;
                    std::thread::sleep(Duration::from_millis(2));
                }
                return Ok(0);
            }
            if let Err(error) = result {
                // Reclaim first, even when error reporting has lost its reader.
                drop(subject.take());
                let errno = error
                    .downcast_ref::<io::Error>()
                    .and_then(io::Error::raw_os_error);
                session.emit(
                    &mut frames,
                    "error",
                    json!({"message":error.to_string(),"errno":errno}),
                )?;
                finishing = Some(Instant::now());
            }
        }
        frames.flush()?;
        if let Some(start) = finishing {
            if frames.output.is_empty() {
                return Ok(0);
            }
            if start.elapsed() > Duration::from_secs(1) {
                return Err("protocol drain timeout".into());
            }
        }
        std::thread::sleep(Duration::from_millis(2));
    }
}

pub fn alive() -> Result<i32> {
    let pid: i32 = std::env::args().nth(2).ok_or("missing pid")?.parse()?;
    if pid <= 0 {
        return Err("pid must be positive".into());
    }
    let rc = unsafe { libc::kill(pid, 0) };
    if rc == 0 {
        Ok(0)
    } else if io::Error::last_os_error().raw_os_error() == Some(libc::ESRCH) {
        Ok(1)
    } else {
        Err(io::Error::last_os_error().into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn arbitrary_byte_encoding() {
        let bytes: Vec<u8> = (0..=255).collect();
        assert_eq!(unhex(&hex(&bytes)).unwrap(), bytes);
        assert!(unhex("f").is_err());
        assert!(unhex("zz").is_err());
        assert!(unhex("é").is_err());
    }
}
