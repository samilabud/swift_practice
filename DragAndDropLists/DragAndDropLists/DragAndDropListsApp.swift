import SwiftUI
import UniformTypeIdentifiers

@main
struct TreeViewApp: App {
    @StateObject private var dragState = DragState()

    var body: some Scene {
        WindowGroup {
            DualListView()
                .environmentObject(dragState)
        }
    }
}

class AnyTreeItem: Identifiable, ObservableObject, Equatable {
    let id = UUID()
    @Published var children: [AnyTreeItem]
    let content: AnyView

    init<Content: View>(content: Content, children: [AnyTreeItem] = []) {
        self.content = AnyView(content)
        self.children = children
    }

    static func == (lhs: AnyTreeItem, rhs: AnyTreeItem) -> Bool {
        return lhs.id == rhs.id
    }
}

class DragState: ObservableObject {
    @Published var draggedItem: AnyTreeItem? = nil
}

class TreeViewModel: ObservableObject {
    @Published var items: [AnyTreeItem]

    init(items: [AnyTreeItem]) {
        self.items = items
    }

    func moveItem(_ draggedItem: AnyTreeItem, to targetItem: AnyTreeItem) {
        if let parent = findParent(of: draggedItem, in: &items) {
            if let index = parent.children.firstIndex(where: { $0 == draggedItem }) {
                parent.children.remove(at: index)
            }
        } else {
            if let index = items.firstIndex(where: { $0 == draggedItem }) {
                items.remove(at: index)
            }
        }
        targetItem.children.append(draggedItem)
    }

    private func findParent(of item: AnyTreeItem, in items: inout [AnyTreeItem]) -> AnyTreeItem? {
        for rootItem in items {
            if rootItem.children.contains(where: { $0 == item }) {
                return rootItem
            }
            if let parent = findParent(of: item, in: &rootItem.children) {
                return parent
            }
        }
        return nil
    }
}

struct TreeRow: View {
    @ObservedObject var item: AnyTreeItem
    @EnvironmentObject var dragState: DragState
    @EnvironmentObject var viewModel: TreeViewModel
    @State private var isTargeted = false
    var allListItems: [AnyTreeItem]

    var body: some View {
        HStack {
            item.content
                .padding(.leading, CGFloat(16 * findLevelOfItem(item, in: allListItems)))
                .padding(.vertical, 8)
                .background(dragState.draggedItem?.id == item.id ? Color.gray.opacity(0.5) : Color.clear)
                .cornerRadius(8)
                .onDrag {
                    dragState.draggedItem = item
                    return NSItemProvider(object: String(item.id.uuidString) as NSString)
                }
                .onDrop(of: [.plainText], isTargeted: $isTargeted) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { (data, error) in
                        DispatchQueue.main.async {
                            guard let data = data as? Data, let idString = String(data: data, encoding: .utf8), let id = UUID(uuidString: idString), let draggedItem = dragState.draggedItem else { return }
                            if draggedItem != item {
                                viewModel.moveItem(draggedItem, to: item)
                            }
                            dragState.draggedItem = nil
                        }
                    }
                    return true
                }

            Spacer()
        }
        .background(isTargeted ? Color.red.opacity(0.3) : Color.clear)
    }
}

func findLevelOfItem(_ item: AnyTreeItem, in treeData: [AnyTreeItem], currentLevel: Int = 0) -> Int {
    for rootItem in treeData {
        if rootItem == item {
            return currentLevel
        }
        let childrenLevel = findLevelOfItem(item, in: rootItem.children, currentLevel: currentLevel + 1)
        if childrenLevel != 0 {
            return childrenLevel
        }
    }
    return 0
}

struct TreeView: View {
    @ObservedObject var item: AnyTreeItem
    @EnvironmentObject var dragState: DragState
    @EnvironmentObject var viewModel: TreeViewModel
    var allListItems: [AnyTreeItem]

    var body: some View {
        VStack(alignment: .leading) {
            TreeRow(item: item, allListItems: allListItems)

            if !item.children.isEmpty {
                ForEach(item.children) { child in
                    TreeView(item: child, allListItems: allListItems)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ListView: View {
    @ObservedObject var viewModel: TreeViewModel

    var body: some View {
        List {
            ForEach(viewModel.items) { item in
                TreeView(item: item, allListItems: viewModel.items)
                    .environmentObject(viewModel)
            }
        }
    }
}

struct DualListView: View {
    @StateObject private var viewModel1 = TreeViewModel(items: sampleData1)
    @StateObject private var viewModel2 = TreeViewModel(items: sampleData2)
    @EnvironmentObject var dragState: DragState

    var body: some View {
        HStack {
            ListView(viewModel: viewModel1)
                .environmentObject(viewModel1)
            ListView(viewModel: viewModel2)
                .environmentObject(viewModel2)
        }
    }
}

// Sample Data
var sampleData1: [AnyTreeItem] = [
    AnyTreeItem(content: VStack { Text("List 1 - Item 1 - 1"); Text("List 1 - Item 1 - 2") }, children: [
        AnyTreeItem(content: Image(systemName: "star")),
        AnyTreeItem(content: Text("List 1 - Item 1.2"), children: [
            AnyTreeItem(content: Text("List 1 - Item 1.2.1")),
            AnyTreeItem(content: Text("List 1 - Item 1.2.2"))
        ])
    ]),
    AnyTreeItem(content: Text("List 1 - Item 2"))
]

var sampleData2: [AnyTreeItem] = [
    AnyTreeItem(content: Image(systemName: "house"), children: [
        AnyTreeItem(content: Image(systemName: "bell")),
        AnyTreeItem(content: Text("List 2 - Item 1.2"), children: [
            AnyTreeItem(content: Image(systemName: "leaf")),
            AnyTreeItem(content: Text("List 2 - Item 1.2.2"))
        ])
    ]),
    AnyTreeItem(content: Text("List 2 - Item 2"))
]
