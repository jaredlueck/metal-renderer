//
//  main.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-03.
//
import Cocoa

func main(argc: Int32, argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32{
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    return NSApplicationMain(argc, argv)
}
main(argc: CommandLine.argc, argv: CommandLine.unsafeArgv)
