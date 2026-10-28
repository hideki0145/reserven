# Reserven

アイテムの利用開始・延長・終了を管理するRailsアプリです。

- Ruby 4.0.9 / Rails 8.1.4
- SQLite(開発・テスト・本番)
- Bootstrap 5.3.8のCSSをCDN配信
- PropshaftでCSS・JavaScriptを配信。Webpacker・CSSコンパイルは不要
- RSpec(モデル・リクエスト・Playwrightによるブラウザテスト)

`/status`画面は、利用可能・利用中・猶予期間中をアイコン付きバッジで表示します。
利用者と曜日付きの利用期限を分けて表示し、自分の利用には`(自分)`を付けます。
利用期限は日本時間の時刻だけで指定します。現在より後の時刻は本日、前の時刻は翌日として扱います。
翌日の期限は一覧上のモーダルで実際の日付を確認して確定します。戻る・Escでは利用状況を変更しません。
JavaScriptや確認用通信が利用できない場合は、サーバ側の確認画面を使用します。
現在と同じ時刻や不正な入力はエラーにします。日付付きのリクエストも未来の日時だけを受け付けます。
開始時の初期値は現在の15分後、延長時は現在と既存期限の遅い方の15分後です。

旧PostgreSQLのデータは移行せず、新規DBで開始します。

## 開発環境

Ruby 4.0.9とBundler 4.0.23を用意します。miseを利用する場合：

`mise.toml`でRubyとブラウザテスト用のNode.jsのバージョンを管理しています。

```sh
cp .env.sample .env
mise install
ruby -v
gem install bundler -v 4.0.23
bin/setup --skip-server
```

`.env`が既にある場合は、コピーで上書きせず必要な設定を追記してください。
開発環境でSlack通知を試す場合は、`.env`の`SLACK_WEBHOOK_URL`のコメントを外し、
開発用チャンネルのWebhook URLへ置き換えます。未設定なら通知しません。
`.env`はGit管理対象外です。

`mise.toml`の`[env]`設定で`.env`を読み込みます。
シェルでmiseを有効化していない場合も、`mise exec -- bin/rails server`で設定を適用して起動できます。
miseを使用しない場合は、必要な環境変数をシェルやプロセス管理ツールで設定してください。
RSpecでは`SLACK_WEBHOOK_URL`を無効化し、実際のSlack通知は送信しません。

`bin/setup`はRails標準の生成内容を維持しており、依存gemのインストール・DB準備後に開発サーバを起動します。上記の`--skip-server`を付けるとサーバを起動しません。Linuxでgemのソースビルドが必要な場合は、コンパイラとSQLite開発用ライブラリなども必要です。

初期管理者は環境変数から作成します。以下はzshの例です。パスワードは画面に表示せず入力します。

```sh
export ADMIN_EMAIL='admin@example.com'
export ADMIN_NAME='管理者'
read -s 'ADMIN_PASSWORD?初期管理者パスワード: '
export ADMIN_PASSWORD
bin/rails db:seed
unset ADMIN_PASSWORD
bin/rails server
```

[ログイン画面](http://localhost:3000/login)へアクセスしてください。
同じメールアドレスで再度seedしても、既存ユーザやパスワードは変更しません。

## テスト

ブラウザテストではNode.js 24系とPlaywrightのChromiumを使用します。アプリの実行・本番アセット生成にはNode.jsは不要です。
画面表示とブラウザテストには、Bootstrapの配信元`cdn.jsdelivr.net`へ接続できる環境が必要です。

```sh
npm ci
bin/playwright install chromium
```

Linuxでブラウザ用のシステムライブラリも必要な場合は、
`bin/playwright install --with-deps chromium`を使用します。

```sh
bundle exec rspec spec/models spec/requests
bundle exec rspec
```

テスト用アセットの出力先は`tmp/test-assets`に分離しています。
本番アセット生成後も`public/assets`のmanifestを参照せず、現在のJavaScriptを検証します。

RSpecのsystem specはCapybaraのPlaywrightドライバで実行します。
Selenium・ChromeDriverは使用しません。
PlaywrightのnpmパッケージはRubyクライアントの対応バージョンと一致させています。
CLIの入口は`bin/playwright`に統一し、未インストールやバージョン不一致は実行前に検出します。
gem更新時は以下で対応バージョンを確認し、
`package.json`と`package-lock.json`も更新してください。

```sh
bundle exec ruby -r playwright -e \
  'puts Playwright::COMPATIBLE_PLAYWRIGHT_VERSION'
```

環境準備・RSpec・自動読み込みチェック・本番アセット生成をまとめて実行する場合は、Rails標準の`bin/ci`を利用できます。初回は上記のブラウザ用システムライブラリを準備してください。

```sh
bin/ci
```

miseからもテストの準備・実行ができます。

```sh
mise run playwright_install
mise run ci
mise run spec
# GUIを表示してブラウザテストを実行する(デスクトップ環境が必要)
mise run spec_headful
```

Linuxのシステムライブラリも含めて準備する場合は、
`mise run playwright_install_with_deps`を実行します。
GUI表示は`PLAYWRIGHT_HEADFUL=1`でも指定できます。
スクリーンショットの保存先は`tmp/capybara/1`です。
`TEST_ENV_NUMBER`がある場合はその値で保存先を分け、CI失敗時は成果物として保存します。

Capybaraの設定は`spec/support/capybara.rb`で管理します。
ログインヘルパーは`RequestSpecHelper`・`SystemSpecHelper`へ分離し、
それぞれrequest spec・system specにのみ読み込みます。
テストデータの作成は`TestRecords`で管理し、system specはすべてPlaywrightで実行します。

認証、ログイン状態の保持、管理者権限、ユーザ・アイテム管理、利用期限と15分の猶予、Slack通知失敗時の挙動、ブラウザでの削除確認・CSS適用を検証します。テストからSlackへの実通信は行いません。

移行に合わせて、猶予期間中の他ユーザによる直接の利用開始リクエスト、利用終了後の延長、利用されていないアイテムの終了操作も適切に拒否するよう修正しています。同時利用開始はトランザクションと一意制約で防ぎます。Slackの通信エラーは利用登録を取り消さず、ログへ記録します。

## 自前サーバへの配置

単一のLinuxサーバにNginx＋Puma＋systemdで配置する構成を想定しています。DockerやFly.ioは使用しません。

1. 専用ユーザ`reserven`、Ruby 4.0.9、Bundler 4.0.23を用意します。
2. アプリを`/srv/reserven/current`へ配置し、書き込み可能な`/srv/reserven/shared/storage`を作成します。
3. `config/deploy/reserven.env.sample`を参考に`/etc/reserven.env`を作成します。実際の秘密情報はリポジトリに保存せず、このファイルを専用ユーザだけが読めるようにします。
4. アプリのディレクトリで、以下を実行します。

   ```sh
   bundle config set --local without 'development test'
   bundle install
   # /etc/reserven.envをシェルで読み込む場合の例
   set -a
   . /etc/reserven.env
   set +a
   bin/rails assets:precompile
   bin/rails db:prepare
   # ADMIN_EMAILとADMIN_PASSWORDを一時的に設定して初期管理者を作成
   bin/rails db:seed
   ```

   `SECRET_KEY_BASE`は`bin/rails secret`で生成し、環境ファイルへ設定します。
   生成した値をログや公開ファイルへ記録しないでください。
   暗号化credentialsは使用しないため、`config/credentials.yml.enc`と`config/master.key`は配置不要です。

5. `config/deploy/reserven.service`を参考にsystemdへ登録します。`ExecStart`のRuby・Bundlerの絶対パスは、サーバのインストール先に合わせて変更してください。
6. `config/deploy/nginx.conf.sample`のドメイン・証明書パスを変更してNginxへ設定し、HTTPSで公開します。

`config/puma.rb`はRails標準のままです。systemdの設定例では`--bind tcp://127.0.0.1:3000`を明示し、Pumaをlocalhostに限定します。直接起動する場合も同じオプションを指定してください。ポートを変更する場合はsystemdとNginx双方の設定を変更します。HTTPSを終端するリバースプロキシの後ろで動かす前提です。`APP_HOST`には公開ドメインを設定します。

### 本番環境の主な設定

| 環境変数 | 用途 |
| --- | --- |
| `RAILS_ENV` | 本番では`production` |
| `SECRET_KEY_BASE` | Cookieの署名・暗号化に使用。再配置時も同じ値を保持 |
| `APP_HOST` | 公開するホスト名 |
| `SQLITE_DATABASE_PATH` | DBの絶対パス。既定は`storage/production.sqlite3` |
| `RAILS_MAX_THREADS` | Pumaのスレッド数。既定3 |
| `SLACK_WEBHOOK_URL` | 任意。設定した場合だけSlackへ通知 |

Slack通知を利用する場合は、SlackアプリのIncoming Webhooksを有効にし、
通知先チャンネルを選んで発行したHTTPSのWebhook URLを`SLACK_WEBHOOK_URL`へ設定してください。
手順は[Slack公式ドキュメント](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/)を参照してください。
投稿先はWebhook URLに紐づくため、チャンネルの環境変数は不要です。
従来の`SLACK_TOKEN`と`SLACK_CHANNEL`は使用しません。既存環境では設定を置き換えてください。
Webhook URLは秘密情報として管理し、Gitやログへ記録しないでください。
未設定の場合は通知せず、通知失敗時も利用開始・延長・終了の処理結果は維持します。
通知はBlock Kitで操作・利用者・期限または状態を表示します。
延長時は変更前後の期限を表示します。通知は利用者・利用期限または状態を縦に並べます。延長時は変更前・変更後の期限を別行に表示します。
日時は日本時間で、`10/28(水) 20:00`のように曜日を付けます。
通知の`text`には読み上げ用の要約を設定します。
Slackのデスクトップ通知はBlock Kit内の文字を優先して抽出するため、
ラベルと値は同じ行に表示して、トーストでの行数を抑えます。
Webhook未設定時は、その要約とスキップ理由を`debug`ログへ記録します。
送信成功時の追加ログはなく、失敗時はHTTPステータスまたは例外クラスを`warn`ログへ記録します。

SQLiteはサーバのローカルディスクに配置し、
リリース更新時にDBファイルを置き換えないようにしてください。
バックアップにはSQLiteのオンラインバックアップ機能、
または`sqlite3 <DBパス> '.backup <バックアップ先>'`を使い、
稼働中のDBファイルだけを単純コピーしないでください。
同時書き込みは直列化されるため、大量の更新や複数サーバへの拡張時は構成を見直します。

Bootstrap 5.3.8のCSSはjsDelivr CDNから読み込みます。
バージョン固定のURLとSRIハッシュをレイアウトに指定し、CSS本体はGit管理に含めません。
更新時はURLのバージョンと`integrity`のハッシュを同時に更新してください。
配布URLとハッシュは[Bootstrap公式の導入例](https://getbootstrap.com/docs/5.3/getting-started/introduction/)で確認できます。
追加の配色は`app/assets/stylesheets/application.css`で管理します。
Bootstrap用のnpm依存・Sassコンパイル・JavaScriptプラグインは使用していません。

## アイコン

Reservenのアイコンは、利用予約を表すカレンダーとチェックを組み合わせたSVGです。
原本は`public/icon.svg`で、濃紺・白・緑の配色を使用しています。
Rails標準のレイアウトから参照される`public/icon.png`も同じデザインです。

PNG・ICOを書き出し直す場合は、Playwrightの準備後に以下を実行します。
この処理は開発時の任意作業で、本番のビルドや起動には不要です。

```sh
mise exec -- node script/export-icons.mjs
```

512pxの`icon.png`、180pxのApple用アイコン、
16・32・48pxを含む`favicon.ico`を書き出します。
PWAのテーマ色もアイコンに合わせていますが、PWAのルートは有効化していません。

## Rails標準生成プロジェクトとの比較

Ruby **4.0.9**、Rails **8.1.4**、Bundler **4.0.23**で実際に生成した内容を基準にしています。
SQLiteは標準設定を使用し、現在使っていないフレームワーク・デプロイツール・検査ツールを
生成オプションで除外しています。
`--skip-test`はRSpecを使用するため、
`--skip-javascript`は既存の通常のJavaScriptをバンドルなしで配信するためです。
`--skip-ci`はGitHub ActionsをRSpec・Playwright向けに管理するためです。

再生成する場合は、プロジェクトのルートから以下を実行します。
既存のRailsプロジェクト内では`rails new`を実行できないため、比較用ディレクトリへ移動します。
`BUNDLE_GEMFILE`でこのプロジェクトのRails 8.1.4を使用し、
`--no-rc`で個人の生成オプションの影響を除きます。

```sh
project_dir="$PWD"
reference_dir=$(mktemp -d /tmp/reserven-rails814.XXXXXX)
cd "$reference_dir"
BUNDLE_GEMFILE="$project_dir/Gemfile" bundle exec rails new reserven \
  --database=sqlite3 \
  --skip-action-mailer --skip-action-mailbox --skip-action-text \
  --skip-active-job --skip-active-storage --skip-action-cable \
  --skip-javascript --skip-hotwire --skip-jbuilder --skip-test \
  --skip-docker --skip-kamal --skip-thruster --skip-solid \
  --skip-rubocop --skip-brakeman --skip-bundler-audit --skip-ci \
  --skip-bundle --skip-decrypted-diffs --no-rc

# 例：Puma設定は生成結果と同一なので差分なし
diff -u reserven/config/puma.rb "$project_dir/config/puma.rb"
# 例：アプリ固有の設定だけを確認
diff -u reserven/config/application.rb "$project_dir/config/application.rb"
cd "$project_dir"
```

主な差分は次のとおりです。標準のコメント・記述順序を残し、必要な追記に留めています。

| 対象 | 標準生成内容からの変更 |
| --- | --- |
| `Gemfile` | Railsの固定、`.ruby-version`の参照、認証・テスト・日本語翻訳用gemの追加 |
| `config/application.rb` | RSpecのジェネレータ指定と`Asia/Tokyo`の追加 |
| `config/database.yml` | 本番DBの永続化先を`SQLITE_DATABASE_PATH`で指定 |
| `config/environments/production.rb` | `APP_HOST`による公開ホスト指定 |
| `app/views/layouts/application.html.erb` | BootstrapのCDN読み込み |
| `config/initializers/locale.rb` | 日本語を既定ロケールに指定する独自ファイル |
| `config/routes.rb` | 標準のヘルスチェック・コメントに業務ルートを追加 |
| `config/ci.rb`・`.github/workflows/ci.yml` | RSpec・Playwright・アセット生成の検証を実行 |
| `.gitignore` | Playwrightのnpm依存の除外を追加 |
| `public/icon.*`など | Reserven用のアイコンへ変更。SVGからPNG・ICOを書き出し |
| `app/views/pwa/manifest.json.erb` | アプリの説明とテーマ色を変更 |
| レイアウト・モデル・コントローラ・seed | 標準の雛形に認証・画面・業務処理を追加 |

`config/puma.rb`、開発・テストの環境設定、`bin/setup`などの標準スクリプト、静的エラーページは生成結果と同一です。暗号化credentialsは使用しないため削除し、秘密情報は環境変数で設定します。

Rails標準の`allow_browser versions: :modern`も反映しています。古いブラウザはHTTP 406の案内画面になります。`/up`は認証なしでアプリの起動状態を確認する標準のエンドポイントです。
