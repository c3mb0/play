//! A deliberately bounded byte-reading subject, with no stdio input buffering.
use std::{
    io::{self, Write},
    thread,
    time::{Duration, Instant},
};

fn readable(timeout_ms: i32) -> io::Result<bool> {
    let mut fd = libc::pollfd {
        fd: 0,
        events: libc::POLLIN,
        revents: 0,
    };
    let result = unsafe { libc::poll(&mut fd, 1, timeout_ms) };
    if result < 0 {
        return Err(io::Error::last_os_error());
    }
    if result == 0 {
        return Ok(false);
    }
    if fd.revents & libc::POLLIN == 0 {
        return Err(io::Error::other(format!(
            "unexpected poll events: {}",
            fd.revents
        )));
    }
    Ok(true)
}

fn byte() -> io::Result<u8> {
    let mut value = 0u8;
    let count = unsafe { libc::read(0, (&mut value as *mut u8).cast(), 1) };
    match count {
        1 => Ok(value),
        -1 => Err(io::Error::last_os_error()),
        _ => Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "expected byte",
        )),
    }
}

fn line(text: &str) -> io::Result<()> {
    let mut output = io::stdout().lock();
    writeln!(output, "{text}")?;
    output.flush()
}

fn main() -> io::Result<()> {
    line("READY")?;
    let deadline = Instant::now() + Duration::from_millis(400);
    let first = if readable(400)? { Some(byte()?) } else { None };
    thread::sleep(deadline.saturating_duration_since(Instant::now()));
    line(&first.map_or_else(|| "WINDOW NONE".into(), |b| format!("WINDOW {b:02x}")))?;
    let mut input: Vec<u8> = first.into_iter().collect();
    while input.len() < 2 {
        if !readable(1000)? {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "final byte deadline",
            ));
        }
        input.push(byte()?);
    }
    if input != b"h\n" {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "expected h newline",
        ));
    }
    line("FINAL 680a")
}
