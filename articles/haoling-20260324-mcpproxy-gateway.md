---
title: "AI エージェントに社内 Kubernetes を安全に見せる MCP 基盤を作った話"
emoji: "☸️"
type: "tech"
topics: ["MCP", "Kubernetes", "OAuth", "Dex"]
published: false
publication_name: "gmomedia"
---

# Claude に Kubernetes を直接触らせています

はいどーも、はおりんです！

突然ですが、こんな状況を想像してください。

「本番 Kubernetes の Pod が落ちてる！ Pod のログが見たい！」

こういうとき、ChatOps 的な観点でいえばコマンドを打てる人が行動できるわけですが、Kubernetes のコマンドに慣れていない人だと、ログひとつ見るのにドキュメントと格闘するはめになります。

では、「自然言語で聞いたら K8s の情報をリアルタイムで返してくれる AI」がいたらどうでしょう。

「dev 環境の web-app Pod のログ見せて」「api Deployment のレプリカ数は？」

…そのまま聞けますね。

弊社では、そういう MCP エンドポイントを Kubernetes 上に立てるべく、現在テスト環境での検証を進めています。Claude Code・Claude.ai・GPTs などの複数クライアントからの接続は確認できており、本番環境への展開ももうすぐというところです。

今回はその構築記録です。

---

# なぜ「各自のローカルで動かす」では足りなかったか

最初は素朴に考えていました。`mcp-server-kubernetes` という NPM パッケージがあって、これを Claude Desktop の設定ファイルに書けば動きます。実際に動きます。

でも、それだと困ることがいくつかありまして。

**Windows の壁**  
`mcp-server-kubernetes` は Node.js 製の stdio サーバーです。stdio サーバーはシェルやパスに依存するため、Windows 環境では動作が不安定になりがちで、「自分の PC では動かない」案件が発生します。

**設定が個人任せ**  
各自が自分の PC に設定を書く = シークレットや設定の管理が個人依存になります。各個人の PC に置くシークレットは、少なければ少ないほどいい。

**クライアントを選ぶ**  
ローカル PC の stdio 設定では、Claude Desktop 以外（Claude.ai Web 版、GPTs など）からはアクセスできません。

そこで「K8s 上に共有エンドポイントを 1 本立てよう」という判断になりました。

---

# 全体構成

作ったものをざっくり図にするとこんな感じです。

![image.png](/images/haoling-20260324-mcpproxy-gateway/Gemini_Generated_Image_gz7nzegz7nzegz7n.jpg)

認証は Dex（OIDC IdP）が担います。OneLogin を Dex の上流コネクタとして使い、社員アカウントで OAuth 認可コードフローをして JWT を取得。JWT を Bearer ヘッダーに載せて MCP プロキシを叩く構成です。

コンポーネントを一覧にするとこうなります。

| コンポーネント | 役割 |
|---|---|
| **MCP プロキシ** ※ | MCP プロキシ。JWT 認証・ツール認可・stdio→HTTP 変換 |
| **Dex** | OIDC IdP。OneLogin を上流に JWT 発行 |
| **mcp-server-kubernetes** | K8s リソースを MCP ツールとして提供 |
| MCPO | MCP → OpenAPI 変換（GPTs 向け） |
| oauth2-proxy | Web UI 用フォワード認証プロキシ |
| OpenResty | openapi.json の servers.url を Lua で動的書き換え |

※ stdio の MCP サーバーを OAuth で保護されたリモート MCP サーバーに変換するオープンソースプロジェクトはいくつか存在します。弊社ではそのうちの 1 つを採用しており、本記事では「MCP プロキシ」と呼びます。

今日のメインは MCP プロキシと Dex です。

---

# 設計で悩んだポイント 6 つ

ここからが本番です。「なんで素朴な構成じゃダメだったか」という話を順番に書きます。

## ① API キーを設定ファイルに書きたくなかった

技術的には、Claude Desktop の設定ファイルに API キーを直書きすれば、OAuth なしでも MCP サーバーに接続できます。でも、それを社内の共有基盤でやるのはちょっと違うな、と感じていました。

設定ファイルに API キーが平文で残る。各自の PC に散らばる。退職者が出たときに鍵を失効させるフローが属人的になる。「動く」けど「整っていない」状態です。

どうせ基盤として整備するなら、認証はちゃんと OAuth でやろう——というのが Dex + OIDC を選んだ経緯です。

結果として副産物もあって、退職者のアクセス遮断が OneLogin 一本化で即時に行えるようになったのは、セキュリティ的においしいポイントでした。

:::ポイント：「動く」より「整っている」を選んだ

## ② stdio サーバーが Windows で動かない → MCP プロキシで変換する

前述のとおり、`mcp-server-kubernetes` は stdio タイプのサーバーです。

stdio サーバーはローカルで使う分には問題ありませんが、社内共有サーバーとして K8s 上に立てるには向きません。しかも Windows 環境では Node.js の stdio サーバーがパス依存・シェル依存でうまく動かないケースが多い。

ここで MCP プロキシの出番です。

**MCP プロキシは stdio サーバーをラップして HTTP（MCP over HTTP）として公開する機能を持っています。**

これにより、サーバー側の K8s の中で stdio サーバーを動かしつつ、クライアントは OS を問わず HTTPS でアクセスできるようになります。

```
Before: 各 PC に stdio サーバー（Windows は詰む）
After:  K8s 上の stdio サーバー → MCP プロキシ → HTTPS でどこからでもアクセス
```

## ③ API トークンをクライアントに保存したくない

「ローカル PC に K8s の API トークンを置く」方式との比較で考えると、OAuth を使う意味がよくわかります。

K8s の API トークンが漏れると、そのトークンを持っているだけで K8s にアクセスできてしまいます。**「シークレットを知っている = リソースにアクセスできる」** の状態です。

OAuth + OneLogin の構成では、この関係が分離されます。

- **「Client Secret を知っている = 認可を求められる」**
- **「OneLogin で認可を得られる = リソースにアクセスできる」**

Client Secret が仮に漏れても、OneLogin の社内アカウントでログインできなければ認可は得られません。K8s の API トークンに比べて、漏れたときに直接できることがずっと少ない。これが OAuth を採用する本質的な理由です。

接続手順を書いた README ページには Client Secret も掲載していますが、その README 自体が OneLogin で保護されているので、見られる人は社員だけという設計にしています。

## ④ Dynamic Client Registration の壁

MCP の認証仕様では、**RFC 7591（Dynamic Client Registration）** に対応したサーバーを想定しています。DCR があると、クライアントが IdP に自分自身を自動登録できるので、クライアントを追加するたびに手動で設定する必要がなくなります。

実際に Auth0 で DCR を試してみたところ、別の問題が見えてきました。

クライアントが自動登録を繰り返すと、IdP 側の「登録済みクライアント」が際限なく増えていきます。管理コンソールを開いたら見たことのないクライアントが大量に並んでいる、という状態です。これは「氾濫」と表現するのが適切で、どれが正規のクライアントか判別できなくなります。

DCR は「自動化できる」一方で「何が登録されているかわからなくなる」というトレードオフがあり、弊社の運用には合わないと判断しました。

現実解として、Dex の `staticClients` にクライアントを手で書く運用にしています。`staticClients` に書いたシークレットは K8s Secret に格納して、閲覧は社内認証ページ経由に限定。手動管理ではありますが、「何が登録されているか一覧で把握できる」という点では DCR より安心感があります。

![image.png](/images/haoling-20260324-mcpproxy-gateway/Gemini_Generated_Image_6zrxl36zrxl36zrx.jpg)

## ⑤ MCP プロキシと Dex の署名鍵ローテーション問題

ここからは運用上のハマりポイントです。

MCP プロキシは **起動時に Dex の JWKS（公開鍵）を読み込んで固定**します。Dex はデフォルトで署名鍵のローテーションが有効になっているため、鍵が更新されると MCP プロキシの JWT 検証が突然エラーになります。

対策として `gateway-dexkey-reloader` というカスタムコントローラーを自作しました。

```
30秒ごとに Dex の signingkeys CRD（カスタムリソース）を監視
→ kid（鍵 ID）の変化を検知
→ kubectl rollout restart deployment/gateway を実行
```

自作というほど複雑なものでもなく、alpine コンテナで kubectl のシェルスクリプトを回しているだけですが、これがないと鍵ローテーションのたびに手動再起動が必要になります。

## ⑥ MCPO が起動直後に空の OpenAPI を返す

GPTs から MCP ツールを使うには、OpenAPI 形式のスキーマが必要です。これを生成してくれるのが MCPO（MCP to OpenAPI）というコンポーネントです。

MCPO は起動直後、MCP サーバーへの接続が確立される前に `paths: {}` の空の OpenAPI を返すことがあります。このタイミングで GPTs がスキャンすると「ツール 0 件」として認識されてしまいます。

こちらも `mcpo-openapi-reloader` を自作して対応しました。

```
30秒ごとに openapi.json を取得
→ paths のキー数が 0 なら kubectl rollout restart deployment/mcpo
→ 再起動後 60秒待機
```

ついでに、MCPO が生成する openapi.json の `servers[0].url` はデフォルトで `http://127.0.0.1:8001` になります。外部クライアントに正しい URL を返すため、OpenResty（Lua）でレスポンスの JSON をパースして servers.url を動的に差し替えています。

地味ですが、これをやらないと GPTs が正しい URL でアクセスできないので必須の対応でした。

---

# まとめ

作ったもの・解決したことをまとめると：

| 課題 | 解決策 |
|---|---|
| API キーを設定ファイルに書きたくなかった | Dex + OIDC で OAuth 基盤を整備 |
| stdio サーバーが Windows で動かない | MCP プロキシで stdio → HTTP 変換 |
| API トークンをクライアントに保存したくない | OAuth + OneLogin でシークレットとアクセス許可を分離 |
| 署名鍵ローテーションで MCP プロキシが壊れる | gateway-dexkey-reloader 自作 |
| MCPO が空の OpenAPI を返す | mcpo-openapi-reloader 自作 |

---

# 今後やりたいこと

- Slack・DB など他ツールを同じ基盤に追加
- ツール認可をユーザーごとに細かく制御

「AI にインフラを安全に見せる」というテーマはこれからどんどん重要になってくると思います。今回作った基盤がそのベースラインになりそうで、2026 年はここを育てる年にしていきたいと思っています。

以上、開発の現場からはおりんがお伝えしましたー！