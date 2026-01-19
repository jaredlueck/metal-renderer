//
//  ShaderProgram.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-04.
//

import Metal

struct ShaderProgramDescriptor {
    let vertexName: String
    let fragmentName: String
    var constants: MTLFunctionConstantValues? = nil
    var library: MTLLibrary?
}

struct ShaderProgram {
    let vertex: MTLFunction
    let fragment: MTLFunction

    init(device: MTLDevice, descriptor: ShaderProgramDescriptor) throws {
        guard let library = descriptor.library ?? device.makeDefaultLibrary() else {
            fatalError("Failed to make default library")
        }
        if let constants = descriptor.constants {
            self.vertex = try library.makeFunction(name: descriptor.vertexName, constantValues: constants)
            self.fragment = try library.makeFunction(name: descriptor.fragmentName, constantValues: constants)
        } else {
            guard let vertex = library.makeFunction(name: descriptor.vertexName) else {
                fatalError("Could not find vertex function")
            }
            guard let fragment = library.makeFunction(name: descriptor.fragmentName) else {
                fatalError("Could not find fragment function")
            }
            self.vertex = vertex
            self.fragment = fragment
        }
    }
}
