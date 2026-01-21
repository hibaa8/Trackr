import SwiftUI

struct CircularProgressView: View {
    var value: Double
    var maxValue: Double
    var color: Color
    var lineWidth: CGFloat = 16
    var size: CGFloat = 180
    
    var progress: Double {
        min(value / maxValue, 1.0)
    }
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
                .frame(width: size, height: size)
            
            // Progress circle
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
        }
    }
}

