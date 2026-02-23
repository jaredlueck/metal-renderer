//
//  main.swift
//  prefilter-environment-map
//

import Foundation
import Metal
import MetalKit
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("Usage: prefilter-environment-map <path_to_vertical_cubemap> [num_mip_levels]")
    exit(1)
}

let numMipLevels = args.count >= 3 ? (Int(args[2]) ?? 5) : 5

let device        = MTLCreateSystemDefaultDevice()!
let commandQueue  = device.makeCommandQueue()!
let library       = device.makeDefaultLibrary()!
let textureLoader = MTKTextureLoader(device: device)

let inputURL      = URL(fileURLWithPath: args[1])
let inputBaseName = inputURL.deletingPathExtension().lastPathComponent
let outputDir     = inputURL.deletingPathExtension().appendingPathExtension("prefiltered")
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// Load the vertical-strip cubemap (6 faces stacked top-to-bottom).
// .SRGB: false — keep values in gamma space so the output PNG matches input brightness.
// (Default sRGB loading would linearize values in the shader, producing a much darker output.)
let cubeTexture = try textureLoader.newTexture(URL: inputURL, options: [
    .cubeLayout: MTKTextureLoader.CubeLayout.vertical,
    .SRGB: false
])
let faceSize = cubeTexture.width

// Linear sampler for smooth environment sampling
let samplerDesc = MTLSamplerDescriptor()
samplerDesc.minFilter    = .linear
samplerDesc.magFilter    = .linear
samplerDesc.mipFilter    = .notMipmapped
samplerDesc.sAddressMode = .clampToEdge
samplerDesc.tAddressMode = .clampToEdge
samplerDesc.rAddressMode = .clampToEdge
let sampler = device.makeSamplerState(descriptor: samplerDesc)!

// MARK: - Helpers

// Create an rgba8Unorm 2D texture with shared storage (CPU-accessible without sync on all devices).
func makeFaceTexture(size: Int) -> MTLTexture {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
    desc.usage       = [.shaderRead, .shaderWrite]
    desc.storageMode = .shared
    return device.makeTexture(descriptor: desc)!
}

// Save an rgba8Unorm CPU buffer as a PNG.
func savePNG(_ data: Data, width: Int, height: Int, to url: URL) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
    let cfData = data as CFData
    guard
        let provider = CGDataProvider(data: cfData),
        let image    = CGImage(width: width, height: height,
                               bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4,
                               space: colorSpace, bitmapInfo: bitmapInfo,
                               provider: provider, decode: nil,
                               shouldInterpolate: false, intent: .defaultIntent),
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { print("savePNG: failed for \(url.lastPathComponent)"); return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Prefilter environment map

let prefilterFn = library.makeFunction(name: "prefilterEnvMap")!
let prefilterPipelineDesc = MTLComputePipelineDescriptor()
prefilterPipelineDesc.computeFunction = prefilterFn
let prefilterPipeline = try device.makeComputePipelineState(
    descriptor: prefilterPipelineDesc, options: [], reflection: nil)

let tw = min(prefilterPipeline.threadExecutionWidth, faceSize)
let th = max(1, prefilterPipeline.maxTotalThreadsPerThreadgroup / tw)
let tgroups = MTLSize(width: (faceSize + tw - 1) / tw, height: (faceSize + th - 1) / th, depth: 1)
let tgSize  = MTLSize(width: tw, height: th, depth: 1)

// Roughness levels evenly spaced from 0 (mirror) to 1 (fully diffuse)
let roughnessLevels: [Float] = (0..<numMipLevels).map { i in
    numMipLevels > 1 ? Float(i) / Float(numMipLevels - 1) : 0.0
}

print("Generating prefiltered environment maps...")
for (mipLevel, var roughness) in roughnessLevels.enumerated() {
    // One 2D texture per face — avoids cube-texture write access limitations on some devices
    let faceTextures = (0..<6).map { _ in makeFaceTexture(size: faceSize) }

    let cmdBuf  = commandQueue.makeCommandBuffer()!
    let encoder = cmdBuf.makeComputeCommandEncoder()!
    encoder.setComputePipelineState(prefilterPipeline)
    encoder.setTexture(cubeTexture, index: 0)
    encoder.setSamplerState(sampler, index: 0)
    encoder.setBytes(&roughness, length: MemoryLayout<Float>.stride, index: 0)

    for var face in 0..<6 {
        encoder.setTexture(faceTextures[face], index: 1)
        encoder.setBytes(&face, length: MemoryLayout<UInt32>.stride, index: 1)
        encoder.dispatchThreadgroups(tgroups, threadsPerThreadgroup: tgSize)
    }
    encoder.endEncoding()
    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    // Assemble 6 faces into a vertical strip matching the input layout
    let bytesPerRow  = faceSize * 4   // rgba8Unorm = 4 bytes/pixel
    let bytesPerFace = bytesPerRow * faceSize
    var strip = Data(count: bytesPerFace * 6)
    strip.withUnsafeMutableBytes { raw in
        let base = raw.baseAddress!
        for face in 0..<6 {
            faceTextures[face].getBytes(
                base.advanced(by: face * bytesPerFace),
                bytesPerRow: bytesPerRow,
                from: MTLRegion(origin: .init(x: 0, y: 0, z: 0),
                                size: .init(width: faceSize, height: faceSize, depth: 1)),
                mipmapLevel: 0)
        }
    }

    let name = "\(inputBaseName)_\(mipLevel + 1).png"
    savePNG(strip, width: faceSize, height: faceSize * 6,
            to: outputDir.appendingPathComponent(name))
    print("  Saved \(name)")
}

// MARK: - BRDF integration LUT
// x-axis: NoV [0,1], y-axis: roughness [0,1]. Output: R=BRDF scale, G=BRDF bias.

print("Generating BRDF LUT...")
let lutSize = 512
let lutDesc = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .rgba8Unorm, width: lutSize, height: lutSize, mipmapped: false)
lutDesc.usage       = [.shaderRead, .shaderWrite]
lutDesc.storageMode = .shared
let lutTexture = device.makeTexture(descriptor: lutDesc)!

let lutFn = library.makeFunction(name: "computeLUT")!
let lutPipelineDesc = MTLComputePipelineDescriptor()
lutPipelineDesc.computeFunction = lutFn
let lutPipeline = try device.makeComputePipelineState(
    descriptor: lutPipelineDesc, options: [], reflection: nil)

let lw = min(lutPipeline.threadExecutionWidth, lutSize)
let lh = max(1, lutPipeline.maxTotalThreadsPerThreadgroup / lw)

let lutCmdBuf  = commandQueue.makeCommandBuffer()!
let lutEncoder = lutCmdBuf.makeComputeCommandEncoder()!
lutEncoder.setComputePipelineState(lutPipeline)
lutEncoder.setTexture(lutTexture, index: 0)
lutEncoder.dispatchThreadgroups(
    MTLSize(width: (lutSize + lw - 1) / lw, height: (lutSize + lh - 1) / lh, depth: 1),
    threadsPerThreadgroup: MTLSize(width: lw, height: lh, depth: 1))
lutEncoder.endEncoding()
lutCmdBuf.commit()
lutCmdBuf.waitUntilCompleted()

var lutData = Data(count: lutSize * lutSize * 4)
lutData.withUnsafeMutableBytes { raw in
    lutTexture.getBytes(
        raw.baseAddress!, bytesPerRow: lutSize * 4,
        from: MTLRegion(origin: .init(x: 0, y: 0, z: 0),
                        size: .init(width: lutSize, height: lutSize, depth: 1)),
        mipmapLevel: 0)
}

savePNG(lutData, width: lutSize, height: lutSize,
        to: outputDir.appendingPathComponent("brdf_lut.png"))
print("  Saved brdf_lut.png")
print("Done.")
