import ComposableArchitecture
import Entity
import Foundation
import IdentifiedCollections
import SwiftUI

// View と Reducer は同じファイルにしておくとすぐに互いの実装を確認できて便利
// Point-Free 公式も同じファイルにするのが好みらしい

// TCA に用意されている Reducer protocol に準拠した構造体
// 準拠させる書き方ではなく @Reducer (Swift Macros) を使う
@Reducer
public struct RepositoryList {
    // MARK: - @Reducer 準拠には State が必要
    // State には機能に必要となる状態を定義する
    // テストで State の変化を assertion 可能にするため、Equatable なものとして定義するのがおすすめ
    @ObservableState
    public struct State: Equatable {
        var repositoryRows: IdentifiedArrayOf<RepositoryRow.State> = []
        var isLoading: Bool = false
        var query: String = ""

        public init() {}
    }

    // MARK: - @Reducer 準拠には Action が必要
    // UI操作からのイベント・SwiftUI ライフサイクルによるイベント・API Request の結果を受け取った際のイベントなど、様々なイベントを定義
    // enum で定義することが一般的
    public enum Action: BindableAction {
        case onAppear
        case searchRepositoriesResponse(Result<[Repository], Error>) // Action に値を渡したい場合は associated value を使う
        case repositoryRows(IdentifiedActionOf<RepositoryRow>)
        case binding(BindingAction<State>)

        /*
         Reducer で Binding を扱えるようにするには、BindableAction と BindingAction という API を利用する
         BindableAction は Action に準拠させるための protocol として機能し、BindableAction protocol に準拠するためには binding(BindingAction<State>) という case を追加する必要がある
         */
    }

    public init() {}

    // MARK: - @Reducer 準拠には body が必要
    // - 何らかの Action が与えられた時に State を現在の値から次の値へと変更する責務
    // - アプリが外の世界で実行すべき処理である Effect を return する責務（API 通信や UserDefaults へのアクセスなどが該当）
    public var body: some ReducerOf<Self> { // ReducerOf<Self> は Reducer<Self.State, Self.Action> の typealias
        BindingReducer() // Binding の処理を行う各なのでこれを body に組み込む必要がある
        // TCA が用意している Reduce API を用いれば上記の責務を表現できる
        Reduce { state, action in
            switch action {
            case .onAppear:
                // 画面表示のタイミングで
                state.isLoading = true // ローディング中 の状態にする
                // 基本的に TCA では Reducer において Effect.run の中でのみ 非同期処理を実行できる
                return .run { send in // Effect.run の closure には Send 型（ @MainActor 付き）が提供されている
                    // await send(.someAction) のような形で Action を発火できる
                    await send(
                        .searchRepositoriesResponse(
                            // GitHub API の search エンドポイントに対してリクエスト
                            Result {
                                let query = "composable"
                                let url = URL(
                                    string: "https://api.github.com/search/repositories?q=\(query)&sort=stars"
                                )!
                                var request = URLRequest(url: url)
                                if let token = Bundle.main.infoDictionary?["GitHubPersonalAccessToken"] as? String {
                                    request.setValue(
                                        "Bearer \(token)",
                                        forHTTPHeaderField: "Authorization"
                                    )
                                }
                                let (data, _) = try await URLSession.shared.data(for: request)
                                let repositories = try jsonDecoder.decode(
                                    GithubSearchResult.self,
                                    from: data
                                ).items
                                return repositories
                            }
                        )
                    )
                }
                // API Request の結果を受け取るための Action の処理
            case let .searchRepositoriesResponse(result):
                state.isLoading = false

                switch result {
                case let .success(response):
                    // レスポンスから子 View の Reducer の配列を作る
                    state.repositoryRows = .init(
                        uniqueElements: response.map {
                            .init(repository: $0)
                        }
                    )
                    return .none
                case let .failure(error):
                    // TODO: Handling error
                    print("Error fetching repositories: \(error)")
                    return .none
                }
            case .repositoryRows:
                return .none
            case .binding:
                return .none
            }
        }
        .forEach(\.repositoryRows, action: \.repositoryRows) {
            RepositoryRow()
        }
        /*
         RepositoryList Reducer で RepositoryRow Reducer を動作させるために、2つを接続する
         RepositoryList Reducer では複数の RepositoryRow Reducer を管理することとなるが
         このように複数のドメインを一つ一つ Composition するための機能として、
         Reducer.forEach という function が用意されている
         今までに定義してきた Row 用の State・Action の KeyPath を引数に指定しつつ、
         クロージャに対して RepositoryRow Reducer を提供することで利用できます。
         */
    }

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

public struct RepositoryListView: View {
    // Reducer と View を繋ぐ Store API
    // 機能におけるランタイムとしての責務
    // - Reducer の実装に従って State を更新するために Action を処理したり、Effect を実行してくれたりする
    let store: StoreOf<RepositoryList> // StoreOf<X> は Store<X.State, X.Action> の typealias

    public init(store: StoreOf<RepositoryList>) {
        self.store = store
    }

    public var body: some View {
        Group {
            // store.someState の形で State を取得できる
            if self.store.isLoading {
                ProgressView()
            } else { // isLoading が false になった == API Response が帰ってきた場合の View を実装
                List {
                    Rectangle()
                        .foregroundStyle(.red)
                    // 子 View は子 Reducer を用いてこのように作れる？
                    ForEach(
                        self.store.scope(
                            state: \.repositoryRows,
                            action: \.repositoryRows
                        ),
                        content: RepositoryRowView.init(store:)
                    )
                }
            }
        }
        .onAppear {
            // store.send(.someAction) という形で Action を送ることができる
            self.store.send(.onAppear)
        }
    }
}

#Preview {
    RepositoryListView(
        // Store には init(initialState:reducer:withDependencies) という initializer がある
        // これの initialState と reducer を最低限提供すれば initialize できる
        store: .init(
            initialState: RepositoryList.State()
        ) {
            RepositoryList()._printChanges() // ._printChanges() をつけると Reducer で起きた Action や State の変化を 出力できる
        }
    )
}
