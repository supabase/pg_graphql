// build.rs
// Build and link libgraphqlparser

extern crate bindgen;
use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let out_dir = env::var("OUT_DIR").unwrap();

    // Build libgraphqlparser
    Command::new("cmake")
        .arg(&format!("-S {}", "submodules/libgraphqlparser"))
        .arg(&format!("-B {}", out_dir))
        .status()
        .unwrap();

    Command::new("make")
        .arg(&format!("-C {}", out_dir))
        .status()
        .unwrap();

    println!("cargo:rustc-link-search=native={}", out_dir);
    println!("cargo:rustc-link-lib=dylib=graphqlparser");
    //println!("cargo:rerun-if-changed=submodule/libgraphqlparser");

    println!("cargo:rustc-link-lib=graphqlparser");

    // Rust Wrapper
    println!("cargo:rerun-if-changed=c/lib.h");

    // The bindgen::Builder is the main entry point
    // to bindgen, and lets you build up options for
    // the resulting bindings.
    let bindings = bindgen::Builder::default()
        // The input header we would like to generate
        // bindings for.
        .header("c/lib.h")
        // Tell cargo to invalidate the built crate whenever any of the
        // included header files changed.
        .parse_callbacks(Box::new(bindgen::CargoCallbacks))
        // Finish the builder and generate the bindings.
        .generate()
        // Unwrap the Result and panic on failure.
        .expect("Unable to generate bindings");

    // Write the bindings to the $OUT_DIR/bindings.rs file.
    let out_path = PathBuf::from(out_dir);
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
