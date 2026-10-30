# Reserven

アイテムの利用開始・延長・終了を管理するRailsアプリです。

- Ruby 4.0.9 / Rails 8.1.4
- SQLite(開発・テスト・本番)
- Bootstrap 5.3.8のCSSをCDN配信
- PropshaftでCSS・JavaScriptを配信。Webpacker・CSSコンパイルは不要
- RSpec(モデル・リクエスト・Playwrightによるブラウザテスト)

`/status`画面は、利用可能・利用中・猶予期間中・期限切れをアイコン付きバッジで表示します。
利用者と曜日付きの利用期限を分けて表示し、自分の利用には`(自分)`を付けます。
期限から15分経過すると、本人には「期限切れ」と、他の利用者が利用を開始できる旨を表示します。
本人は延長・利用終了を引き続き操作できます。他の利用者には「利用可能」と表示します。
他の利用者が利用を開始した後は、元の利用者による延長・利用終了はできません。
無効化したアイテムは「利用停止中」を優先し、本人の利用終了だけを受け付けます。
利用状態と開始・延長・終了の可否はItemモデルで判定し、画面とコントローラで共通利用します。
768px未満の画面ではアイテムごとのカード表示に切り替え、名前・利用状況・操作を縦に並べます。
長いアイテム名や利用者名は折り返し、横スクロールなしで操作できます。768px以上では表形式で表示します。
ユーザ一覧・アイテム一覧・利用状況画面はIDの昇順で表示し、編集や無効化で並び順を変えません。
利用状況は10分ごとに自動更新します。時刻を変更している間は自動更新を停止し、元の値に戻すと再開します。
最終更新時刻と更新ボタンを表示し、入力を変更した状態で手動更新する場合は破棄の確認を行います。
利用期限は日本時間の時刻だけで指定します。現在より後の時刻は本日、前の時刻は翌日として扱います。
翌日の期限は一覧上のモーダルで実際の日付を確認して確定します。戻る・Escでは利用状況を変更しません。
JavaScriptや確認用通信が利用できない場合は、サーバ側の確認画面を使用します。
現在と同じ時刻や不正な入力はエラーにします。日付付きのリクエストも未来の日時だけを受け付けます。
開始時の初期値は現在の15分後、延長時は現在と既存期限の遅い方の15分後です。

旧PostgreSQLのデータは移行せず、新規DBで開始します。

## 利用データと履歴

利用開始ごとにUsageを1件保存し、延長時は同じレコードの終了予定日時を更新します。
利用終了時には終了操作日時・操作した利用者・終了理由を記録し、レコードを残します。
現在の利用状況と過去の履歴は同じテーブルから取得し、現在状況専用のStatusは使用しません。
期間予約もこの利用データを使う方針ですが、現段階では即時利用のみを実装しています。

猶予期間終了後に別の利用者が利用を開始した場合は、元の利用を「別の利用への切替」として閉じます。
この日時は切替操作の日時であり、実際に利用をやめた日時を推定したものではありません。
期限の経過だけではレコードを閉じず、既存の延長・利用終了の動作を維持します。

利用開始時点の対象名・利用者名と、終了操作時点の操作した利用者名を保存します。
ユーザ・アイテムを変更・削除しても、終了済みの利用レコードと記録時の名前は残ります。
保存するのは1回の利用と最終的な終了予定日時であり、延長のたびの変更履歴やSlackの配信履歴ではありません。
利用の登録者・最終更新者もIDと記録時点の名前で保存します。既存の記録には推測で補完せず、不明として残します。
利用開始時は本人を登録者・最終更新者に設定し、延長・終了・切替時に最終更新者を更新します。
ログイン利用者は`/history`で全員分の終了・切替済み履歴を確認できます。
対象・利用者・自分で絞り込み、削除済みの対象や利用者も記録時の名前で探せます。
終了・切替日時の降順で25件ずつ表示し、ページ移動時も絞り込み条件を保持します。
スマートフォンではカード表示に切り替わります。

### 旧利用状況からの切替

反映時はアプリを停止してSQLiteをバックアップし、`bin/rails db:migrate`を実行してください。
**旧statusesテーブルは削除し、利用中・終了済みを問わず旧利用状況は引き継ぎません。**
ユーザ・アイテムは保持し、全対象を未利用の状態として切り替えます。切替後の利用開始から記録します。
利用中の情報が必要な場合は、反映前に確認・控えを取り、反映後に改めて利用を開始してください。

旧利用状況を復元できないため、このマイグレーションはロールバックできません。
切り戻す場合はアプリを停止し、旧コードと切替前のDBバックアップをセットで復元します。
その場合、切替後の記録はバックアップに含まれない点に注意してください。

## ユーザ管理

最後の有効な管理者は、削除・管理者権限の解除・アカウント無効化ができません。
利用終了していないアイテムがあるユーザは、期限を過ぎていても削除できません。
利用終了後に削除するか、利用情報を保持したままアカウントを無効化してください。
アカウントを無効にするとログインできなくなり、既存セッションとログイン保持Cookieも利用できません。
無効中にアクセスしなかった既存セッションは、再有効化後に利用を再開できます。
ログイン保持Cookieは無効化時に失効します。無効化では利用状況を削除しません。
パスワード変更時も以前のログイン保持Cookieを失効させます。ログイン済みのセッションは維持します。
ユーザ一覧・詳細の日時は`yyyy/mm/dd hh:mm:ss`形式で表示します。
更新時は`bin/rails db:migrate`でアカウント状態のカラムを追加してください。既存ユーザは有効のままです。

## アイテム管理

アイテムを無効にすると、新規利用と延長を停止します。無効で未利用のものは利用状況画面に表示しません。
利用終了の操作が済んでいない場合は、期限を過ぎても利用者・期限と「利用停止中」を表示し、本人の終了操作を許可します。
無効化しても利用情報は保持し、終了後に利用状況画面から非表示になります。管理者一覧には常に表示します。
利用中のアイテムは削除できません。利用終了後に削除するか、無効化してください。
アイテム一覧・詳細の日時はユーザ画面と同じI18nの`timestamp`書式を使用します。
更新時は`bin/rails db:migrate`を実行してください。既存アイテムは有効のままです。

## ログインの試行制限

同じIPからのログイン送信は、成功・失敗を含めて3分間に10回までです。
11回目以降はHTTP 429と再試行の案内を返します。ログイン画面の表示・ログアウト・利用操作は制限しません。
制限は時間経過で解除され、アカウントを永久にロックすることはありません。
専用のメモリ内カウンタを使うため、DB変更やRedisの追加は不要です。
現在の単一Pumaプロセス構成を前提とし、再起動でリセットされます。複数プロセス・複数サーバではカウンタの共有が必要です。
同じIPを共有する利用者は同じ枠を使います。
Nginxの配置例では`X-Forwarded-For`を`$remote_addr`で上書きし、接続元による偽装を避けます。
既存のNginx設定もこの配置例に合わせ、Pumaをlocalhostに限定してください。

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

メールアドレスは登録・更新・ログイン・seed時に前後の空白を除去し、小文字として扱います。
既存データにも`bin/rails db:migrate`で同じ処理を適用します。移行時はアプリを停止してください。
正規化後に重複するアドレスがある場合は、変更前に移行を停止して対象ユーザIDを表示します。
旧バージョンの管理画面で対象アドレスを修正し、アプリを停止して移行を再実行してください。
このデータ移行は元の大文字小文字・空白を復元できないため、ロールバックには対応しません。

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
通知内容は`SlackUsageNotification`で組み立て、`SlackNotifier`で同期送信します。
接続・読み取りのタイムアウトはそれぞれ5秒です。
通知はBlock Kitで操作・利用者・期限または状態を表示します。
延長時は変更前後の期限を表示します。通知は利用者・利用期限または状態を縦に並べます。延長時は変更前・変更後の期限を別行に表示します。
日時は日本時間で、`10/28(水) 20:00`のように曜日を付けます。
通知の`text`には読み上げ用の要約を設定します。
Slackのデスクトップ通知はBlock Kit内の文字を優先して抽出するため、
ラベルと値は同じ行に表示して、トーストでの行数を抑えます。
Webhook未設定時は、その要約とスキップ理由を`debug`ログへ記録します。
送信成功時の追加ログはなく、失敗時はHTTPステータスまたは例外クラスを`warn`ログへ記録します。

### SQLiteのバックアップ

SQLiteはサーバのローカルディスクに配置し、
リリース更新時にDBファイルを置き換えないようにしてください。
バックアップはSQLite CLIの`.backup`で取得します。稼働中でも取得できます。
稼働中のDBファイルだけを単純コピーしないでください。

アプリのディレクトリで、配置ユーザとして実行します。`sqlite3`コマンドが必要です。
既定の`storage/production.sqlite3`を使用している場合：

```sh
backup_file="storage/production-$(date +%Y%m%d-%H%M%S).sqlite3"
test -f "storage/production.sqlite3" && \
  sqlite3 "storage/production.sqlite3" ".backup '$backup_file'"
```

`production-20261029-090000.sqlite3`のように、取得日時を付けて同じディレクトリへ保存します。
`test -f`で元のDBが存在する場合だけ実行し、パス間違いによる空のDB作成を防ぎます。

本番の環境変数で`SQLITE_DATABASE_PATH`を指定している場合は、実際の保存先を使います。
systemdの配置例では、シェルにも`/etc/reserven.env`を読み込んでから実行してください。

```sh
set -a
. /etc/reserven.env
set +a

database_path="${SQLITE_DATABASE_PATH:?本番DBのパスを設定してください}"
backup_file="${database_path%.sqlite3}-$(date +%Y%m%d-%H%M%S).sqlite3"
test -f "$database_path" && sqlite3 "$database_path" ".backup '$backup_file'"
```

コマンドが正常終了したことを確認してください。バックアップの整合性は、保存したファイルを指定して確認できます。

```sh
sqlite3 -readonly "$backup_file" 'PRAGMA quick_check;'
```

`ok`が返れば簡易的な整合性チェックは成功です。
DB移行時はアプリ停止後にバックアップを取得し、更新後の動作確認が済むまで保管してください。
同時書き込みは直列化されるため、大量の更新や複数サーバへの拡張時は構成を見直します。

### アセットの配信

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
