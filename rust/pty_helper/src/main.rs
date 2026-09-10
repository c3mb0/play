//! Phase B: single-threaded, one-shot mechanism. No experiment vocabulary.
mod port;
use serde_json::{json, Value};
use std::{
    fs::File,
    io::{self, Read, Write},
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::process::CommandExt,
    },
    process::{Child, Command, Stdio},
    time::{Duration, Instant},
};

fn os_failure(operation: &str) -> io::Error {
    let error = io::Error::last_os_error();
    eprintln!(
        "{}",
        json!({"event":"os_error", "operation":operation,
        "errno":error.raw_os_error(), "message":error.to_string()})
    );
    error
}

fn number(value: &Value, key: &str) -> Result<u64, Box<dyn std::error::Error>> {
    value[key]
        .as_u64()
        .ok_or_else(|| format!("missing/invalid unsigned {key}").into())
}

fn native_number<T: TryFrom<u64>>(
    value: &Value,
    key: &str,
) -> Result<T, Box<dyn std::error::Error>> {
    T::try_from(number(value, key)?)
        .map_err(|_| format!("{key} exceeds platform field width").into())
}

struct ChildOwner(Child);
impl Drop for ChildOwner {
    fn drop(&mut self) {
        if matches!(self.0.try_wait(), Ok(Some(_))) {
            return;
        }
        // Direct-child ownership only at this checkpoint. No descendant contract.
        if let Err(e) = self.0.kill() {
            eprintln!(
                "{}",
                json!({"event":"cleanup_error", "operation":"kill", "errno":e.raw_os_error(), "message":e.to_string()})
            );
        }
        let deadline = Instant::now() + Duration::from_secs(1);
        loop {
            match self.0.try_wait() {
                Ok(Some(_)) => return,
                Err(e) => {
                    eprintln!(
                        "{}",
                        json!({"event":"cleanup_error", "operation":"try_wait", "errno":e.raw_os_error(), "message":e.to_string()})
                    );
                    return;
                }
                Ok(None) => {}
            }
            if Instant::now() >= deadline {
                eprintln!("{}", json!({"event":"cleanup_timeout", "pid":self.0.id()}));
                return;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
    }
}

fn run() -> Result<i32, Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 6 || args[4] != "--" {
        return Err(
            "usage: pty_helper CONFIG_JSON slave|ctty DEADLINE_MS -- EXECUTABLE [ARGS...]".into(),
        );
    }
    let controlling = match args[2].as_str() {
        "slave" => false,
        "ctty" => true,
        _ => return Err("mode must be slave or ctty".into()),
    };
    let timeout: u64 = args[3].parse()?;
    if !(1..=60_000).contains(&timeout) {
        return Err("deadline must be 1..60000 ms".into());
    }
    let config: Value = serde_json::from_reader(File::open(&args[1])?)?;
    let t = &config["termios"];
    let w = &config["dimensions"];
    // Start from zeroed platform storage; copy only defined fields, never padding.
    let mut term: libc::termios = unsafe { std::mem::zeroed() };
    term.c_iflag = native_number(t, "iflag")?;
    term.c_oflag = native_number(t, "oflag")?;
    term.c_cflag = native_number(t, "cflag")?;
    term.c_lflag = native_number(t, "lflag")?;
    let cc = t["cc"].as_array().ok_or("cc must be an array")?;
    if cc.len() != term.c_cc.len() {
        return Err("cc length differs from platform NCCS".into());
    }
    for (dst, src) in term.c_cc.iter_mut().zip(cc) {
        *dst = src.as_u64().ok_or("invalid cc value")?.try_into()?;
    }
    let ispeed: libc::speed_t = native_number(t, "ispeed")?;
    let ospeed: libc::speed_t = native_number(t, "ospeed")?;
    unsafe {
        if libc::cfsetispeed(&mut term, ispeed) < 0 {
            return Err(os_failure("cfsetispeed").into());
        }
        if libc::cfsetospeed(&mut term, ospeed) < 0 {
            return Err(os_failure("cfsetospeed").into());
        }
    }
    let mut win = libc::winsize {
        ws_row: number(w, "rows")?.try_into()?,
        ws_col: number(w, "cols")?.try_into()?,
        ws_xpixel: number(w, "xpixel")?.try_into()?,
        ws_ypixel: number(w, "ypixel")?.try_into()?,
    };
    let (mut master_fd, mut slave_fd) = (-1, -1);
    unsafe {
        if libc::openpty(
            &mut master_fd,
            &mut slave_fd,
            std::ptr::null_mut(),
            &mut term,
            &mut win,
        ) < 0
        {
            return Err(os_failure("openpty").into());
        }
    }
    // Immediately establish RAII ownership, including every setup failure path.
    let mut master = unsafe { File::from_raw_fd(master_fd) };
    let slave = unsafe { File::from_raw_fd(slave_fd) };
    for fd in [master.as_raw_fd(), slave.as_raw_fd()] {
        if unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) } < 0 {
            return Err(os_failure("fcntl(FD_CLOEXEC)").into());
        }
    }
    let flags = unsafe { libc::fcntl(master_fd, libc::F_GETFL) };
    if flags < 0 {
        return Err(os_failure("fcntl(F_GETFL)").into());
    }
    if unsafe { libc::fcntl(master_fd, libc::F_SETFL, flags | libc::O_NONBLOCK) } < 0 {
        return Err(os_failure("fcntl(O_NONBLOCK)").into());
    }
    let mut command = Command::new(&args[5]);
    command
        .args(&args[6..])
        .stdin(Stdio::from(slave.try_clone()?))
        .stdout(Stdio::from(slave.try_clone()?))
        .stderr(Stdio::from(slave));
    unsafe {
        // No allocations, locks, formatting or experiment logic after fork.
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
    let started = Instant::now();
    let spawned = command.spawn();
    // Command retains its configured slave descriptors; close before reading EOF.
    drop(command);
    let mut child = ChildOwner(spawned.inspect_err(|error| {
        eprintln!(
            "{}",
            json!({"event":"os_error", "operation":"spawn/pre_exec",
            "errno":error.raw_os_error(), "message":error.to_string()})
        );
    })?);
    eprintln!(
        "{}",
        json!({"event":"spawned", "helper_version":env!("CARGO_PKG_VERSION"),
        "pid":child.0.id(), "new_session":true, "controlling_tty":controlling})
    );
    let mut output = Vec::new();
    let mut eof = false;
    let mut status = None;
    let result: Result<(), Box<dyn std::error::Error>> = loop {
        if started.elapsed() >= Duration::from_millis(timeout) {
            eprintln!("{}", json!({"event":"timeout", "deadline_ms":timeout}));
            break Err("deadline exceeded".into());
        }
        let mut buffer = [0u8; 8192];
        if !eof {
            match master.read(&mut buffer) {
                Ok(0) => {
                    eof = true;
                    eprintln!("{}", json!({"event":"master_end", "read":0}));
                }
                Ok(n) => {
                    output.extend_from_slice(&buffer[..n]);
                    if output.len() > 1_048_576 {
                        break Err("output exceeds 1 MiB mechanism limit".into());
                    }
                }
                Err(e)
                    if e.kind() == io::ErrorKind::WouldBlock
                        || e.kind() == io::ErrorKind::Interrupted => {}
                // Linux PTY master closure is EIO; preserve its native form.
                Err(e) if cfg!(target_os = "linux") && e.raw_os_error() == Some(libc::EIO) => {
                    eof = true;
                    eprintln!(
                        "{}",
                        json!({"event":"master_end", "errno":e.raw_os_error(), "message":e.to_string()})
                    );
                }
                Err(e) => break Err(e.into()),
            }
        }
        if status.is_none() {
            match child.0.try_wait() {
                Ok(s) => status = s,
                Err(e) => break Err(e.into()),
            }
        }
        if eof && status.is_some() {
            break Ok(());
        }
        std::thread::sleep(Duration::from_millis(2));
    };
    // Release machine resources before emitting potentially blocking stream output.
    drop(master);
    drop(child);
    std::io::stdout().write_all(&output)?;
    result?;
    use std::os::unix::process::ExitStatusExt;
    let status = status.ok_or("missing child status")?;
    eprintln!(
        "{}",
        json!({"event":"child_exit", "code":status.code(), "signal":status.signal(),
        "elapsed_ns":started.elapsed().as_nanos()})
    );
    Ok(status.code().unwrap_or(128 + status.signal().unwrap_or(0)))
}

fn main() {
    let mode = std::env::args().nth(1);
    let result = match mode.as_deref() {
        Some("--port") => port::relay(),
        Some("--guardian") => port::guardian(),
        Some("--alive") => port::alive(),
        _ => run(),
    };
    let code = match result {
        Ok(code) => code,
        Err(error) => {
            eprintln!(
                "{}",
                json!({"event":"helper_error", "message":error.to_string()})
            );
            125
        }
    };
    std::process::exit(code);
}
