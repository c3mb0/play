use std::io::{self, IsTerminal, Write};

fn main() -> io::Result<()> {
    if io::stdin().is_terminal() {
        print!("input> ");
        io::stdout().flush()?;
    }
    let mut line = String::new();
    if io::stdin().read_line(&mut line)? == 0 {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "expected one line",
        ));
    }
    print!("received: {line}");
    io::stdout().flush()
}
