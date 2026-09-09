#!/usr/bin/swift
import AppKit

guard CommandLine.arguments.count == 3 else {
    fputs("usage: set-file-icon.swift <icon.icns> <file>\n", stderr)
    exit(1)
}

let iconURL = URL(fileURLWithPath: CommandLine.arguments[1])
let file = CommandLine.arguments[2]
guard let image = NSImage(contentsOf: iconURL) else {
    fputs("Could not read icon \(iconURL.path)\n", stderr)
    exit(1)
}
guard NSWorkspace.shared.setIcon(image, forFile: file, options: []) else {
    fputs("Could not set icon on \(file)\n", stderr)
    exit(1)
}
