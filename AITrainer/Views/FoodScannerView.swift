//
//  FoodScannerView.swift
//  AITrainer
//
//  Camera interface for food scanning
//

import SwiftUI
import AVFoundation
import PhotosUI

struct FoodScannerView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = FoodScannerViewModel()
    @State private var showingImagePicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var scanMode: ScanMode = .camera
    
    enum ScanMode {
        case camera, barcode, label
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Camera preview
                CameraPreview(session: viewModel.captureSession)
                    .ignoresSafeArea()
                
                // Overlay UI
                VStack {
                    // Top bar
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding()
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        
                        Spacer()
                        
                        Text("Just snap a pic")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Spacer()

                        Button(action: {
                            showingImagePicker = true
                        }) {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding()
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Recognition labels (if analyzing)
                    if viewModel.isAnalyzing {
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Analyzing food...")
                                .foregroundColor(.white)
                                .font(.subheadline)
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                    } else if !viewModel.detectedIngredients.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(viewModel.detectedIngredients, id: \.self) { ingredient in
                                Text(ingredient)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.white.opacity(0.3)))
                            }
                        }
                        .padding()
                    }
                    
                    Spacer()
                    
                    // Bottom controls
                    VStack(spacing: 20) {
                        // Scan mode buttons
                        HStack(spacing: 40) {
                            ScanModeButton(
                                icon: "camera.fill",
                                label: "Scan Food",
                                isSelected: scanMode == .camera
                            ) {
                                scanMode = .camera
                            }
                            
                            ScanModeButton(
                                icon: "barcode.viewfinder",
                                label: "Barcode",
                                isSelected: scanMode == .barcode
                            ) {
                                scanMode = .barcode
                            }
                            
                            ScanModeButton(
                                icon: "doc.text.viewfinder",
                                label: "Food Label",
                                isSelected: scanMode == .label
                            ) {
                                scanMode = .label
                            }
                        }
                        
                        // Capture button
                        Button(action: {
                            viewModel.capturePhoto()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 70, height: 70)
                                
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 85, height: 85)
                            }
                        }
                        .disabled(viewModel.isAnalyzing)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $viewModel.showNutritionDetails) {
            if let recognition = viewModel.recognitionResult {
                NutritionDetailsView(recognition: recognition)
            }
        }
        .onAppear {
            viewModel.startCamera()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
        .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { newPhoto in
            if let newPhoto = newPhoto {
                viewModel.handlePhotoSelection(newPhoto)
            }
        }
    }
}

struct ScanModeButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .foregroundColor(.white)
            .frame(width: 80)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.3) : Color.clear)
            )
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = context.coordinator.previewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

#Preview {
    FoodScannerView()
}
