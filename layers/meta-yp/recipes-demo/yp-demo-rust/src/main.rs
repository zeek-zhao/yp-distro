use std::env;
use std::process;

const NAME: &str = env!("CARGO_PKG_NAME");
const VERSION: &str = env!("CARGO_PKG_VERSION");

fn main() {
    let mut args = env::args_os().skip(1);
    let option = args.next();

    if args.next().is_some() {
        eprintln!("{NAME}: expected at most one option; use --help");
        process::exit(2);
    }

    match option.as_deref().and_then(|arg| arg.to_str()) {
        None if option.is_none() => println!("Hello from {NAME}!"),
        Some("--json") => println!(
            "{{\"name\":\"{NAME}\",\"version\":\"{VERSION}\",\"message\":\"Hello from {NAME}!\"}}"
        ),
        Some("--version") => println!("{NAME} {VERSION}"),
        Some("--help") => println!(
            "Usage: {NAME} [--json | --version | --help]\n\
             --json     Print a JSON greeting\n\
             --version  Print the package version\n\
             --help     Print this help"
        ),
        _ => {
            eprintln!("{NAME}: unknown option; use --help");
            process::exit(2);
        }
    }
}
