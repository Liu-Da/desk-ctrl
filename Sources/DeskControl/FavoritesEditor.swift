import DeskCore
import SwiftUI

private typealias EditorState<Value> = SwiftUI.State<Value>

struct FavoritesEditor: View {
    @ObservedObject var controller: DeskController
    let onDismiss: () -> Void
    private let originalDeskID: UUID?
    @EditorState private var draft: [DeskFavorite]
    @EditorState private var selectedID: UUID?
    @EditorState private var nameText: String
    @EditorState private var heightText: String
    @EditorState private var error: String?

    init(controller: DeskController, onDismiss: @escaping () -> Void) {
        self.controller = controller
        self.onDismiss = onDismiss
        originalDeskID = controller.deskID
        let first = controller.favorites.first
        _draft = EditorState(initialValue: controller.favorites)
        _selectedID = EditorState(initialValue: first?.id)
        _nameText = EditorState(initialValue: first?.name ?? "")
        _heightText = EditorState(initialValue: first.map { format($0.heightCM) } ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("编辑收藏位置")
                .font(.system(size: 20, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 25)
                .frame(height: 64)
            HStack(spacing: 0) {
                list
                detail
            }
        }
        .frame(width: 780, height: 470)
        .foregroundStyle(DeskStyle.ink)
        .background(Color.white)
        .tint(DeskStyle.blue)
    }

    private var list: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("收藏位置").font(.system(size: 14, weight: .medium))
                Spacer()
                Text("\(draft.count) / \(FavoriteStore.maximumCount)")
                    .font(.system(size: 12)).foregroundStyle(DeskStyle.secondary)
                Button(action: addFavorite) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 24, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(draft.count < FavoriteStore.maximumCount ? DeskStyle.blue : DeskStyle.secondary.opacity(0.4))
                .disabled(draft.count >= FavoriteStore.maximumCount)
                .accessibilityLabel("新增收藏")
                .help("新增收藏")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            VStack(spacing: 3) {
                ForEach(draft) { favorite in
                    Button { select(favorite.id) } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "star")
                                .font(.system(size: 21))
                                .foregroundStyle(DeskStyle.secondary)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(favorite.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                Text("\(format(favorite.heightCM)) cm")
                                    .font(.system(size: 12)).monospacedDigit()
                                    .foregroundStyle(DeskStyle.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 62)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedID == favorite.id ? DeskStyle.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 8)
        }
        .frame(width: 245)
        .frame(maxHeight: .infinity)
        .background(DeskStyle.sidebar)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if selectedID != nil {
                Text("名称")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DeskStyle.secondary)
                TextField("收藏名称", text: $nameText)
                    .deskField()
                    .padding(.top, 10)
                    .accessibilityLabel("收藏名称")
                Text("高度")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DeskStyle.secondary)
                    .padding(.top, 30)
                HStack(spacing: 12) {
                    TextField("高度", text: $heightText)
                        .deskField()
                        .frame(width: 135)
                        .accessibilityLabel("收藏高度，厘米")
                    Text("cm").font(.system(size: 15)).foregroundStyle(DeskStyle.secondary)
                    Button("使用当前高度") {
                        if let height = controller.heightCM { heightText = format(height); error = nil }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DeskStyle.blue)
                    .buttonStyle(.plain)
                    .disabled(!controller.baseKnown || !controller.hasFreshHeight || controller.isMoving)
                }
                .padding(.top, 10)
            } else {
                Spacer()
                Button("新增收藏", action: addFavorite)
                    .buttonStyle(FlatButtonStyle())
                    .frame(maxWidth: .infinity)
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
            Spacer(minLength: 24)
            HStack(spacing: 10) {
                Button("删除收藏", action: deleteFavorite)
                    .buttonStyle(FlatButtonStyle(kind: .destructive))
                    .disabled(selectedID == nil)
                Spacer()
                Button("取消", action: onDismiss)
                    .buttonStyle(FlatButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .buttonStyle(FlatButtonStyle(kind: .primary))
                    .disabled(!controller.canEditFavorites || controller.isMoving)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @discardableResult
    private func storeCurrentForm() -> Bool {
        guard let selectedID, let index = draft.firstIndex(where: { $0.id == selectedID }) else { return true }
        guard let height = deskNumber(heightText), (controller.minCM...controller.maxCM).contains(height) else {
            error = "高度须在 \(format(controller.minCM))–\(format(controller.maxCM)) cm 内"
            return false
        }
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        draft[index].customName = name.isEmpty || name == "收藏 \(draft[index].number)" ? nil : name
        draft[index].heightCM = (height * 10).rounded() / 10
        error = nil
        return true
    }

    private func loadForm(_ id: UUID?) {
        selectedID = id
        let favorite = draft.first { $0.id == id }
        nameText = favorite?.name ?? ""
        heightText = favorite.map { format($0.heightCM) } ?? ""
        error = nil
    }

    private func select(_ id: UUID) {
        guard id != selectedID, storeCurrentForm() else { return }
        loadForm(id)
    }

    private func addFavorite() {
        guard draft.count < FavoriteStore.maximumCount, storeCurrentForm(),
              let number = FavoriteStore.nextNumber(in: draft) else { return }
        let height = Swift.min(controller.maxCM, Swift.max(controller.minCM,
            controller.baseKnown ? controller.heightCM ?? controller.minCM : controller.minCM))
        let favorite = DeskFavorite(number: number, heightCM: (height * 10).rounded() / 10)
        draft.append(favorite)
        loadForm(favorite.id)
    }

    private func deleteFavorite() {
        guard let selectedID, let index = draft.firstIndex(where: { $0.id == selectedID }) else { return }
        draft.remove(at: index)
        loadForm(draft.isEmpty ? nil : draft[Swift.min(index, draft.count - 1)].id)
    }

    private func save() {
        guard storeCurrentForm() else { return }
        guard let originalDeskID, controller.saveFavorites(draft, for: originalDeskID) else {
            error = controller.status
            return
        }
        onDismiss()
    }
}
