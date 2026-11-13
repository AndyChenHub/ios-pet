import CoreGraphics
import Foundation
import UIKit

public enum SpritesheetLayoutMode: String, CaseIterable, Identifiable, Sendable {
    case autoStandard8x9 = "Standard 8×9 Sheet"
    case grid4x4 = "4×4 Sprite Grid"
    case strip4 = "Horizontal Strip (4)"
    case singleImage = "Single Dog Sticker"

    public var id: String { rawValue }

    public var helperDescription: String {
        switch self {
        case .autoStandard8x9:
            return "Matches Alfie & Teddy 8×9 spritesheets (all 10 actions)."
        case .grid4x4:
            return "Slices a 4-column × 4-row pixel-art character sheet."
        case .strip4:
            return "Slices a 4-frame horizontal animation strip."
        case .singleImage:
            return "Turns a single transparent pet PNG into a bouncy animated pet."
        }
    }
}

public enum SpritesheetImportError: LocalizedError {
    case invalidImage
    case emptySpritesheet

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Couldn't read that image file. Please select a valid PNG or image."
        case .emptySpritesheet:
            return "The selected image appears completely transparent or empty."
        }
    }
}

/// Manages built-in + custom user-created pets, spritesheet slicing, and micro-sprite caching.
public final class CustomPetStore: @unchecked Sendable {
    public static let shared = CustomPetStore()

    private static let rosterDefaultsKey = "islandpup.v3.petRoster"
    private static let targetCanvasSize = 144

    private let fileManager = FileManager.default
    private let frameCache: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.countLimit = 48
        return cache
    }()
    private var microCache: [String: [String: [Data]]] = [:]
    private var cachedRoster: [PetProfile]?
    private let lock = NSLock()

    private init() {}

    private var baseDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = appSupport.appendingPathComponent("IslandPupCustomPets", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Roster Persistence

    public func loadRoster() -> [PetProfile] {
        lock.lock()
        if let cached = cachedRoster {
            lock.unlock()
            return cached
        }
        lock.unlock()

        if let data = UserDefaults.standard.data(forKey: Self.rosterDefaultsKey),
           let decoded = try? JSONDecoder().decode([PetProfile].self, from: data),
           !decoded.isEmpty {
            let normalized = ensureBuiltInsPresent(in: decoded)
            lock.lock()
            cachedRoster = normalized
            lock.unlock()
            return normalized
        }
        let initial = [PetProfile.defaultAlfie, PetProfile.defaultTeddy]
        saveRoster(initial)
        return initial
    }

    public func saveRoster(_ roster: [PetProfile]) {
        let normalized = ensureBuiltInsPresent(in: roster)
        lock.lock()
        cachedRoster = normalized
        lock.unlock()
        if let data = try? JSONEncoder().encode(normalized) {
            UserDefaults.standard.set(data, forKey: Self.rosterDefaultsKey)
        }
    }

    private func ensureBuiltInsPresent(in list: [PetProfile]) -> [PetProfile] {
        var result = list
        if !result.contains(where: { $0.id == PetProfile.defaultAlfie.id }) {
            result.insert(.defaultAlfie, at: 0)
        }
        if !result.contains(where: { $0.id == PetProfile.defaultTeddy.id }) {
            let idx = min(1, result.count)
            result.insert(.defaultTeddy, at: idx)
        }
        return result
    }

    @discardableResult
    public func updatePet(id: String, name: String, colorPreset: PetColorPreset? = nil) -> PetProfile? {
        var roster = loadRoster()
        guard let idx = roster.firstIndex(where: { $0.id == id }) else { return nil }
        let cleanName = SharedStorage.sanitizeDisplayText(name, maxLength: 18)
        if !cleanName.isEmpty {
            roster[idx].name = cleanName
        }
        if let colorPreset {
            roster[idx].colorPreset = colorPreset
        }
        saveRoster(roster)
        return roster[idx]
    }

    public func deleteCustomPet(id: String) {
        var roster = loadRoster()
        guard let idx = roster.firstIndex(where: { $0.id == id && $0.isCustom }) else { return }
        let removed = roster.remove(at: idx)
        saveRoster(roster)

        if let sheetID = removed.customSheetID {
            lock.lock()
            microCache.removeValue(forKey: sheetID)
            lock.unlock()
            let dir = baseDirectory.appendingPathComponent(sheetID, isDirectory: true)
            try? fileManager.removeItem(at: dir)
        }
    }

    // MARK: - Spritesheet Import & Slicing

    public func importSpritesheet(
        from image: UIImage,
        name: String,
        colorPreset: PetColorPreset,
        layout: SpritesheetLayoutMode
    ) throws -> PetProfile {
        guard let cgSheet = Self.normalizedCGImage(from: image, maxDimension: 3072) else {
            throw SpritesheetImportError.invalidImage
        }

        let slicedByAction = try Self.sliceAllActions(cgSheet: cgSheet, layout: layout)
        let sheetID = "sheet-" + UUID().uuidString.lowercased()
        let sheetDir = baseDirectory.appendingPathComponent(sheetID, isDirectory: true)
        try fileManager.createDirectory(at: sheetDir, withIntermediateDirectories: true)

        var microMap: [String: [Data]] = [:]

        for action in PetAction.allCases {
            let cgFrames = slicedByAction[action] ?? slicedByAction[.idle] ?? []
            guard !cgFrames.isEmpty else { continue }

            for (idx, frameCG) in cgFrames.enumerated() {
                let uiFrame = UIImage(cgImage: frameCG)
                if let png = uiFrame.pngData() {
                    let fileURL = sheetDir.appendingPathComponent("\(action.rawValue)_\(idx).png")
                    try? png.write(to: fileURL, options: .atomic)
                }
            }

            // Encode 2 distinct pose frames (frame 0 and midpoint frame) for Dynamic Island & remote sync
            let firstCG = cgFrames[0]
            let midCG = cgFrames[cgFrames.count / 2]
            var encodedPair: [Data] = []
            if let f0 = MicroSpriteCodec.encodeFrame(firstCG) {
                encodedPair.append(f0)
            }
            if cgFrames.count > 1, let f1 = MicroSpriteCodec.encodeFrame(midCG) {
                encodedPair.append(f1)
            }
            if !encodedPair.isEmpty {
                microMap[action.rawValue] = encodedPair
            }
        }

        guard !microMap.isEmpty else {
            try? fileManager.removeItem(at: sheetDir)
            throw SpritesheetImportError.emptySpritesheet
        }

        if let microData = try? JSONEncoder().encode(microMap) {
            let microURL = sheetDir.appendingPathComponent("micro.json")
            try? microData.write(to: microURL, options: .atomic)
        }

        lock.lock()
        microCache[sheetID] = microMap
        lock.unlock()

        let cleanName = SharedStorage.sanitizeDisplayText(name, maxLength: 18)
        let finalName = cleanName.isEmpty ? "Buddy" : cleanName

        let profile = PetProfile(
            id: "custom-" + UUID().uuidString.lowercased(),
            name: finalName,
            subtitle: "Custom Spritesheet Pet",
            builtInCharacter: nil,
            customSheetID: sheetID,
            colorPreset: colorPreset
        )

        var roster = loadRoster()
        roster.append(profile)
        saveRoster(roster)
        return profile
    }

    /// Generates an instant in-memory preview of `idle` frames before saving a custom pet.
    public static func previewFrames(from image: UIImage, layout: SpritesheetLayoutMode) -> [UIImage] {
        guard let cg = normalizedCGImage(from: image, maxDimension: 2048),
              let map = try? sliceAllActions(cgSheet: cg, layout: layout),
              let idle = map[.idle], !idle.isEmpty else {
            return []
        }
        return idle.map { UIImage(cgImage: $0) }
    }

    // MARK: - Frame Retrieval

    public func inAppFrames(for sheetID: String, action: PetAction) -> [UIImage] {
        let cacheKey = "\(sheetID):\(action.rawValue)" as NSString
        if let cached = frameCache.object(forKey: cacheKey) as? [UIImage], !cached.isEmpty {
            return cached
        }

        let sheetDir = baseDirectory.appendingPathComponent(sheetID, isDirectory: true)
        var loaded: [UIImage] = []
        for idx in 0..<8 {
            let url = sheetDir.appendingPathComponent("\(action.rawValue)_\(idx).png")
            if fileManager.fileExists(atPath: url.path),
               let img = UIImage(contentsOfFile: url.path) {
                loaded.append(img)
            }
        }

        if loaded.isEmpty, action != .idle {
            return inAppFrames(for: sheetID, action: .idle)
        }

        if !loaded.isEmpty {
            frameCache.setObject(loaded as NSArray, forKey: cacheKey)
        }
        return loaded
    }

    public func microFrames(for sheetID: String, action: PetAction) -> [Data]? {
        lock.lock()
        if let map = microCache[sheetID] {
            lock.unlock()
            return map[action.rawValue] ?? map[PetAction.idle.rawValue]
        }
        lock.unlock()

        let microURL = baseDirectory
            .appendingPathComponent(sheetID, isDirectory: true)
            .appendingPathComponent("micro.json")
        guard let data = try? Data(contentsOf: microURL),
              let decoded = try? JSONDecoder().decode([String: [Data]].self, from: data) else {
            return nil
        }

        lock.lock()
        microCache[sheetID] = decoded
        lock.unlock()

        return decoded[action.rawValue] ?? decoded[PetAction.idle.rawValue]
    }

    public func makeSnapshot(for profile: PetProfile, action: PetAction) -> IslandPetSnapshot {
        let customMicro: [Data]?
        if let sheetID = profile.customSheetID {
            customMicro = microFrames(for: sheetID, action: action)
        } else {
            customMicro = nil
        }
        return IslandPetSnapshot(
            id: profile.id,
            name: profile.name,
            builtInCharacter: profile.builtInCharacter,
            customSheetID: profile.customSheetID,
            colorPreset: profile.colorPreset,
            action: action,
            customMicroFrames: customMicro
        )
    }

    // MARK: - CoreGraphics Grid Slicing

    private static let standard8x9Spec: [(PetAction, Int, [Int])] = [
        (.idle, 0, [0, 1, 2, 3, 4, 5]),
        (.sleeping, 5, [5, 7, 6, 7]),
        (.waving, 3, [0, 1, 2, 3]),
        (.jumping, 4, [0, 1, 2, 3, 4, 0]),
        (.runRight, 1, [0, 1, 2, 3, 4, 5, 6, 7]),
        (.runLeft, 2, [0, 1, 2, 3, 4, 5, 6, 7]),
        (.waiting, 6, [0, 1, 2, 3, 4, 5]),
        (.working, 7, [0, 1, 2, 3, 4, 5]),
        (.review, 8, [0, 1, 2, 3, 4, 5]),
        (.dizzy, 5, [0, 1, 2, 3, 4, 5, 6, 7])
    ]

    private static func sliceAllActions(
        cgSheet: CGImage,
        layout: SpritesheetLayoutMode
    ) throws -> [PetAction: [CGImage]] {
        let sheetW = cgSheet.width
        let sheetH = cgSheet.height
        guard sheetW >= 16, sheetH >= 16 else {
            throw SpritesheetImportError.invalidImage
        }

        // Determine effective layout (auto-fallback if user picked 8x9 on a wide strip or tiny single image)
        let effectiveLayout: SpritesheetLayoutMode
        if layout == .autoStandard8x9 {
            let ratio = Double(sheetH) / Double(sheetW)
            if ratio < 0.42 {
                effectiveLayout = .strip4
            } else if sheetW < 96 || sheetH < 96 {
                effectiveLayout = .singleImage
            } else {
                effectiveLayout = .autoStandard8x9
            }
        } else {
            effectiveLayout = layout
        }

        switch effectiveLayout {
        case .autoStandard8x9:
            return try sliceStandard8x9(cgSheet: cgSheet)
        case .grid4x4:
            return try sliceGrid4x4(cgSheet: cgSheet)
        case .strip4:
            return try sliceHorizontalStrip(cgSheet: cgSheet, count: 4)
        case .singleImage:
            return try sliceSingleSticker(cgSheet: cgSheet)
        }
    }

    private static func sliceStandard8x9(cgSheet: CGImage) throws -> [PetAction: [CGImage]] {
        let cols = 8
        let rows = 9
        let cellW = cgSheet.width / cols
        let cellH = cgSheet.height / rows
        guard cellW >= 8, cellH >= 8 else {
            return try sliceSingleSticker(cgSheet: cgSheet)
        }

        var result: [PetAction: [CGImage]] = [:]
        var fallbackCells: [CGImage] = []

        for (action, row, colIndices) in standard8x9Spec {
            var rawCells: [CGImage] = []
            for col in colIndices where col < cols && row < rows {
                let rect = CGRect(x: col * cellW, y: row * cellH, width: cellW, height: cellH)
                if let cropped = cgSheet.cropping(to: rect), alphaBoundingBox(of: cropped) != nil {
                    rawCells.append(cropped)
                }
            }

            if rawCells.isEmpty, !fallbackCells.isEmpty {
                rawCells = fallbackCells
            }

            let normalized = normalizeCellsToEvenSquareFrames(rawCells)
            if !normalized.isEmpty {
                result[action] = normalized
                if fallbackCells.isEmpty {
                    fallbackCells = rawCells
                }
            }
        }

        if result.isEmpty {
            return try sliceSingleSticker(cgSheet: cgSheet)
        }
        return result
    }

    private static func sliceGrid4x4(cgSheet: CGImage) throws -> [PetAction: [CGImage]] {
        let cellW = cgSheet.width / 4
        let cellH = cgSheet.height / 4
        guard cellW >= 8, cellH >= 8 else {
            return try sliceSingleSticker(cgSheet: cgSheet)
        }

        var rows: [[CGImage]] = []
        for r in 0..<4 {
            var rowCells: [CGImage] = []
            for c in 0..<4 {
                let rect = CGRect(x: c * cellW, y: r * cellH, width: cellW, height: cellH)
                if let cell = cgSheet.cropping(to: rect), alphaBoundingBox(of: cell) != nil {
                    rowCells.append(cell)
                }
            }
            if !rowCells.isEmpty {
                rows.append(normalizeCellsToEvenSquareFrames(rowCells))
            }
        }

        guard !rows.isEmpty else {
            return try sliceSingleSticker(cgSheet: cgSheet)
        }

        var result: [PetAction: [CGImage]] = [:]
        for (i, action) in PetAction.allCases.enumerated() {
            result[action] = rows[i % rows.count]
        }
        return result
    }

    private static func sliceHorizontalStrip(cgSheet: CGImage, count: Int) throws -> [PetAction: [CGImage]] {
        let cellW = max(1, cgSheet.width / count)
        var cells: [CGImage] = []
        for c in 0..<count {
            let rect = CGRect(x: c * cellW, y: 0, width: cellW, height: cgSheet.height)
            if let cell = cgSheet.cropping(to: rect), alphaBoundingBox(of: cell) != nil {
                cells.append(cell)
            }
        }
        let frames = normalizeCellsToEvenSquareFrames(cells)
        guard !frames.isEmpty else {
            return try sliceSingleSticker(cgSheet: cgSheet)
        }
        var result: [PetAction: [CGImage]] = [:]
        for action in PetAction.allCases {
            result[action] = frames
        }
        return result
    }

    private static func sliceSingleSticker(cgSheet: CGImage) throws -> [PetAction: [CGImage]] {
        guard let bbox = alphaBoundingBox(of: cgSheet),
              let trimmed = cgSheet.cropping(to: bbox) else {
            throw SpritesheetImportError.emptySpritesheet
        }

        // Synthesize a cute 2-frame breathing/bounce cycle from a single sticker
        let frame0 = renderCenteredOnSquare(trimmed, canvasSize: targetCanvasSize, yOffsetRatio: 0.02, scaleBoost: 1.0)
        let frame1 = renderCenteredOnSquare(trimmed, canvasSize: targetCanvasSize, yOffsetRatio: -0.04, scaleBoost: 1.03)
        let pair = [frame0, frame1].compactMap { $0 }
        guard pair.count == 2 else {
            throw SpritesheetImportError.emptySpritesheet
        }

        var result: [PetAction: [CGImage]] = [:]
        for action in PetAction.allCases {
            result[action] = pair
        }
        return result
    }

    private static func normalizeCellsToEvenSquareFrames(_ cells: [CGImage]) -> [CGImage] {
        guard !cells.isEmpty else { return [] }
        let boxes = cells.compactMap { alphaBoundingBox(of: $0) }
        guard !boxes.isEmpty else { return [] }

        let minX = boxes.map(\.minX).min()!
        let minY = boxes.map(\.minY).min()!
        let maxX = boxes.map(\.maxX).max()!
        let maxY = boxes.map(\.maxY).max()!
        let unionRect = CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))

        var frames: [CGImage] = []
        for cell in cells {
            if let cropped = cell.cropping(to: unionRect),
               let square = renderCenteredOnSquare(cropped, canvasSize: targetCanvasSize, yOffsetRatio: 0, scaleBoost: 1.0) {
                frames.append(square)
            }
        }

        if frames.count == 1 {
            frames.append(frames[0])
        } else if frames.count % 2 != 0 {
            frames.append(frames[0])
        }
        return frames
    }

    private static func renderCenteredOnSquare(
        _ cg: CGImage,
        canvasSize: Int,
        yOffsetRatio: CGFloat,
        scaleBoost: CGFloat
    ) -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: canvasSize,
            height: canvasSize,
            bitsPerComponent: 8,
            bytesPerRow: canvasSize * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
        ctx.interpolationQuality = .high

        let pad: CGFloat = 8
        let avail = CGFloat(canvasSize) - pad * 2
        let scale = min(avail / CGFloat(cg.width), avail / CGFloat(cg.height)) * scaleBoost
        let w = CGFloat(cg.width) * scale
        let h = CGFloat(cg.height) * scale
        let x = (CGFloat(canvasSize) - w) * 0.5
        let y = (CGFloat(canvasSize) - h) * 0.5 - yOffsetRatio * CGFloat(canvasSize)

        ctx.draw(cg, in: CGRect(x: x, y: y, width: w, height: h))
        return ctx.makeImage()
    }

    private static func alphaBoundingBox(of cg: CGImage) -> CGRect? {
        let w = cg.width
        let h = cg.height
        guard w > 0, h > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w
        var minY = h
        var maxX = -1
        var maxY = -1

        for y in 0..<h {
            let rowBase = y * w * 4
            for x in 0..<w {
                if pixels[rowBase + x * 4 + 3] > 20 {
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func normalizedCGImage(from image: UIImage, maxDimension: CGFloat) -> CGImage? {
        let srcSize = image.size
        guard srcSize.width > 1, srcSize.height > 1 else { return image.cgImage }

        let scaleRatio = min(1.0, maxDimension / max(srcSize.width, srcSize.height))
        let targetW = max(16, Int((srcSize.width * scaleRatio).rounded()))
        let targetH = max(16, Int((srcSize.height * scaleRatio).rounded()))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetW, height: targetH), format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        }
        return rendered.cgImage
    }
}
