use serde_json::{json, Value};
use std::{fs::OpenOptions, io::Write, mem::MaybeUninit};

fn os_error() -> Value {
    let e = std::io::Error::last_os_error();
    json!({"errno": e.raw_os_error(), "message": e.to_string()})
}

fn terminal(fd: libc::c_int) -> Value {
    // Each result retains its own immediate errno; unavailable is not false/zero.
    unsafe {
        let tty = if libc::isatty(fd) == 1 {
            json!({"value": true})
        } else {
            json!({"value": false, "error": os_error()})
        };
        let fg = libc::tcgetpgrp(fd);
        let foreground = if fg < 0 {
            json!({"error": os_error()})
        } else {
            json!({"value": fg})
        };
        let mut term = MaybeUninit::<libc::termios>::uninit();
        let termios = if libc::tcgetattr(fd, term.as_mut_ptr()) == 0 {
            let t = term.assume_init();
            json!({"iflag": t.c_iflag, "oflag": t.c_oflag, "cflag": t.c_cflag,
                "lflag": t.c_lflag, "cc": t.c_cc.to_vec(),
                "ispeed": libc::cfgetispeed(&t), "ospeed": libc::cfgetospeed(&t),
                "canonical": t.c_lflag & libc::ICANON != 0,
                "echo": t.c_lflag & libc::ECHO != 0,
                "isig": t.c_lflag & libc::ISIG != 0})
        } else {
            json!({"error": os_error()})
        };
        let mut win = MaybeUninit::<libc::winsize>::uninit();
        let dimensions = if libc::ioctl(fd, libc::TIOCGWINSZ, win.as_mut_ptr()) == 0 {
            let w = win.assume_init();
            json!({"rows": w.ws_row, "cols": w.ws_col, "xpixel": w.ws_xpixel, "ypixel": w.ws_ypixel})
        } else {
            json!({"error": os_error()})
        };
        json!({"fd": fd, "isatty": tty, "foreground_pgrp": foreground,
            "termios": termios, "dimensions": dimensions})
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 || args[1] != "--snapshot" {
        return Err("usage: topology_probe --snapshot NEW_FILE".into());
    }
    let observation = unsafe {
        let sid = libc::getsid(0);
        let session = if sid < 0 {
            json!({"error": os_error()})
        } else {
            json!({"value": sid})
        };
        let controlling = libc::open(c"/dev/tty".as_ptr(), libc::O_RDONLY | libc::O_NOCTTY);
        let controlling_tty = if controlling < 0 {
            json!({"accessible": false, "error": os_error()})
        } else {
            libc::close(controlling);
            json!({"accessible": true})
        };
        json!({"schema": 1, "pid": libc::getpid(), "ppid": libc::getppid(),
            "sid": session, "pgrp": libc::getpgrp(), "controlling_tty": controlling_tty,
            "stdio": [terminal(0), terminal(1), terminal(2)]})
    };
    let bytes = serde_json::to_vec(&observation)?;
    // Side-channel capture preserves the actual attachment of all three stdio FDs.
    let mut snapshot = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&args[2])?;
    snapshot.write_all(&bytes)?;
    snapshot.write_all(b"\n")?;
    snapshot.sync_all()?;
    std::io::stdout().write_all(&bytes)?;
    std::io::stdout().write_all(b"\n")?;
    Ok(())
}
