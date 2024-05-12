import ComposableArchitecture
import Entity
import Foundation
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
    public var body: some ReducerOf<Self> { // ReducerOf<Self> は Reducer<Self.State, Self.Action> の typealias
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
                                let repositories = try self.jsonDecoder.decode(
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
                    state.repositories = response
                    return .none
                case let .failure(error):
                    // TODO: Handling error
                    print("Error fetching repositories: \(error)")
                    return .none
                }
            }
        }
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
                  ForEach(store.repositories, id: \.id) { repository in
                    Button {
                        // TODO: 後ほど実装
                    } label: {
                      VStack(alignment: .leading, spacing: 8) {
                        Text(repository.fullName)
                          .font(.title2.bold())
                        Text(repository.description ?? "")
                          .font(.body)
                          .lineLimit(2)
                        HStack(alignment: .center, spacing: 32) {
                          Label(
                            title: {
                              Text("\(repository.stargazersCount)")
                                .font(.callout)
                            },
                            icon: {
                              Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            }
                          )
                          Label(
                            title: {
                              Text(repository.language ?? "")
                                .font(.callout)
                            },
                            icon: {
                              Image(systemName: "text.word.spacing")
                                .foregroundStyle(.gray)
                            }
                          )
                        }
                      }
                      .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                  }
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
