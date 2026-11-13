import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AddPetSheet: View {
    enum Mode: Identifiable {
        case createNew
        case editExisting(PetProfile)

        var id: String {
            switch self {
            case .createNew: return "create-new"
            case .editExisting(let p): return "edit-\(p.id)"
            }
        }
    }

    let mode: Mode
    @ObservedObject var syncService: PairSyncService
    @Environment(\.dismiss) private var dismiss

    @State private var petName: String = ""
    @State private var selectedColor: PetColorPreset = .mintGreen
    @State private var layoutMode: SpritesheetLayoutMode = .autoStandard8x9
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showFileImporter: Bool = false
    @State private var importedUIImage: UIImage?
    @State private var previewFrames: [UIImage] = []
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    previewStageCard

                    nameInputSection

                    colorPresetSection

                    if case .createNew = mode {
                        spritesheetSourceSection
                        layoutPickerSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 4)
                    }

                    actionButtonsSection
                }
                .padding(20)
            }
            .background(Color(red: 0.06, green: 0.07, blue: 0.11).ignoresSafeArea())
            .navigationTitle(isEditing ? "Customize Pet" : "New Spritesheet Pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: populateInitialValues)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let uiImg = UIImage(data: data) {
                        await MainActor.run {
                            applyImportedImage(uiImg)
                        }
                    } else {
                        await MainActor.run {
                            errorMessage = "Couldn't load that photo. Try a PNG spritesheet image."
                        }
                    }
                }
            }
            .onChange(of: layoutMode) { _, newLayout in
                if let importedUIImage {
                    previewFrames = CustomPetStore.previewFrames(from: importedUIImage, layout: newLayout)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.png, .image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessed { url.stopAccessingSecurityScopedResource() }
                    }
                    if let data = try? Data(contentsOf: url),
                       let uiImg = UIImage(data: data) {
                        applyImportedImage(uiImg)
                    } else {
                        errorMessage = "Couldn't read that image file."
                    }
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var isEditing: Bool {
        if case .editExisting = mode { return true }
        return false
    }

    // MARK: - Sections

    private var previewStageCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(selectedColor.color.opacity(0.22))
                    .frame(width: 108, height: 108)
                    .overlay(
                        Circle()
                            .strokeBorder(selectedColor.color.opacity(0.65), lineWidth: 2)
                    )

                if case .editExisting(let existing) = mode {
                    AnimatedPetSpriteView(
                        profile: existing,
                        action: .idle,
                        size: 88,
                        driver: .liveTimeline
                    )
                } else if !previewFrames.isEmpty {
                    TimelineView(.periodic(from: .now, by: 1.0 / 6.0)) { context in
                        let idx = abs(Int(floor(context.date.timeIntervalSinceReferenceDate * 6.0))) % previewFrames.count
                        Image(uiImage: previewFrames[idx])
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(selectedColor.color)
                        Text("Pick Sheet")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }

            Text(petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed Pup" : petName)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var nameInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PET NAME")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))

            TextField("Name your pet (e.g. Mochi, Alfie, Biscuit)", text: $petName)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.08))
                )

            Text("Shown on the Dynamic Island on both connected phones.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var colorPresetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ISLAND THEME COLOR")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 10)], spacing: 10) {
                ForEach(PetColorPreset.allCases) { preset in
                    let isSelected = selectedColor == preset
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedColor = preset
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 14, height: 14)
                            Text(preset.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? preset.color.opacity(0.24) : Color.white.opacity(0.07))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(isSelected ? preset.color : Color.white.opacity(0.1), lineWidth: isSelected ? 1.8 : 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var spritesheetSourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IMPORT SPRITESHEET")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("From Photos", systemImage: "photo.on.rectangle.angled")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white.opacity(0.12))
                        )
                }

                Button {
                    showFileImporter = true
                } label: {
                    Label("From Files", systemImage: "folder.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white.opacity(0.12))
                        )
                }
            }
        }
    }

    private var layoutPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SHEET FORMAT")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))

            Picker("Sheet Format", selection: $layoutMode) {
                ForEach(SpritesheetLayoutMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.08))
            )

            Text(layoutMode.helperDescription)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
        }
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button {
                saveChanges()
            } label: {
                HStack {
                    if isSaving {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "sparkles")
                        Text(isEditing ? "Save Pet Name & Theme" : "Create Pet & Select")
                            .fontWeight(.heavy)
                    }
                }
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(canSave ? Color.white : Color.white.opacity(0.35))
                )
            }
            .disabled(!canSave || isSaving)

            if case .editExisting(let existing) = mode, existing.isCustom {
                Button(role: .destructive) {
                    Task {
                        await syncService.deleteCustomPet(id: existing.id)
                        dismiss()
                    }
                } label: {
                    Label("Delete Custom Pet", systemImage: "trash")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.red.opacity(0.9))
                        .padding(.top, 4)
                }
            }
        }
    }

    private var canSave: Bool {
        let trimmed = petName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .editExisting:
            return !trimmed.isEmpty
        case .createNew:
            return !trimmed.isEmpty && importedUIImage != nil && !previewFrames.isEmpty
        }
    }

    // MARK: - Logic

    private func populateInitialValues() {
        switch mode {
        case .createNew:
            guard FeatureFlags.enableCustomPetCreation else {
                dismiss()
                return
            }
            petName = ""
            selectedColor = .mintGreen
        case .editExisting(let profile):
            petName = profile.name
            selectedColor = profile.colorPreset
        }
    }

    private func applyImportedImage(_ image: UIImage) {
        errorMessage = nil
        importedUIImage = image
        let generated = CustomPetStore.previewFrames(from: image, layout: layoutMode)
        previewFrames = generated
        if generated.isEmpty {
            errorMessage = "That image looked completely transparent. Try another PNG spritesheet."
        } else if petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            petName = "Buddy"
        }
    }

    private func saveChanges() {
        errorMessage = nil
        isSaving = true

        Task {
            switch mode {
            case .editExisting(let existing):
                await syncService.renamePet(
                    id: existing.id,
                    newName: petName,
                    colorPreset: selectedColor
                )
                isSaving = false
                dismiss()

            case .createNew:
                guard let importedUIImage else {
                    isSaving = false
                    return
                }
                do {
                    _ = try await syncService.addCustomPet(
                        from: importedUIImage,
                        name: petName,
                        colorPreset: selectedColor,
                        layout: layoutMode
                    )
                    isSaving = false
                    dismiss()
                } catch {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
