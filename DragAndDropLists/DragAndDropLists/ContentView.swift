//
//  ContentView.swift
//  DragAndDropLists
//
//  Created by Samil Abud on 7/18/24.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
            VStack {
                Toggle(isOn: .constant(true)) {
                    Text("Custom Toggle")
                }
                Text("Additional Info")
            }
            .contentShape(Rectangle()) // Make the entire VStack tappable for the drag gesture
            .simultaneousGesture( // Combine drag and tap gestures
                DragGesture().onChanged { _ in
                    // This is intentionally empty to prevent the Toggle's default behavior
                }
            )
        }
}

#Preview {
    ContentView()
}
