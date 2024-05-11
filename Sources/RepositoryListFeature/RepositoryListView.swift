import Composable ComposableArchitecture
import Entity
import Foundation

// TCA に用意されている Reducer protocol に準拠した構造体
// 準拠させる書き方ではなく @Reducer (Swift Macros) を使う

@Reducer
public struct RepositoryList {
    // MARK: - @Reducer 準拠には State が必要
    // State には機能に必要となる状態を定義する
    // テストで State の変化を assertion 可能にするため、Equatable なものとして定義するのがおすすめ
    @ObservableState
    public struct State: Equatable {
        var repositories: [Repository] = []
        var isLoading: Bool = false
        
        public init() {}
    }
    
    // MARK: - @Reducer 準拠には Action が必要
    // UI操作からのイベント・SwiftUI ライフサイクルによるイベント・API Request の結果を受け取った際のイベントなど、様々なイベントを定義
    // enum で定義することが一般的
    public enum Action {
        case onAppear
        case searchRepositoriesResponse(Result<[Repository], Error>) // Action に値を渡したい場合は associated value を使う
    }
    
    public init() {}
    
    // MARK: - @Reducer 準拠には body が必要
    // - 何らかの Action が与えられた時に State を現在の値から次の値へと変更する責務
    // - アプリが外の世界で実行すべき処理である Effect を return する責務（API 通信や UserDefaults へのアクセスなどが該当）
    // ReducerOf<Self> は Reducer<Self.State, Self.Action> の typealias（TCA では XOf<Y> のような typealias がいくつか出てくる）
    public var body: some ReducerOf<Self> {
        // TCA が用意している Reduce API を用いれば上記の責務を表現できる
        Reduce { state, action in
            switch action {
            // 画面表示のタイミングで
            case .onAppear:
                state.isLoading = true // ローディング中 の状態にする
                
                // 基本的に TCA では Reducer において Effect.run の中でのみ 非同期処理を実行できる
                return .run { send in // Effect.run の closure には Send 型（ @MainActor 付き）が提供されている
                    // await send(.some Action) のような形でに2の Action を発火できる
                    await send(
                        .searchRepositoriesResponse(
                            // GitHub API の search エンドポイントに対してリクエスト
                            Result {
                                let query = "composable"
                                let url = URL(string: "https://api.github.com/search/repositories?q=\(query)&sort=stars")!
                                var request = URLRequest(url: url)
                                if let token = Bundle.main.infoDictionary?["GitHubPersonalAccessToken"] as? String {
                                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                }
                                let (data, _) = try await URLSession.shared.data(for: request)
                                let repositories = try self.jsonDecoder.decode(GithubSearchResult.self, from: data).items
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
                    state.repositories = response
                    return .none
                case .failure:
                    // TODO: Handling error
                    return .none
                }
            }
        }
    }
    
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
