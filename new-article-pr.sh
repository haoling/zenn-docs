#!/usr/bin/env bash

set -eux

# 記事名と記事slugを対話形式で入力させる
read -p "記事名を入力してください: " title
read -p "記事slugを入力してください: " slug

# 記事slugを使って `articles/${slug}.md` にmarkdownファイルを作成する
touch articles/${slug}.md

# frontmatterを記載する
echo "---" > articles/${slug}.md
echo "title: \"$title\"" >> articles/${slug}.md

# ランダムな絵文字を生成する
emojis=("😀" "😁" "😂" "🤣" "😃" "😄" "😅" "😆" "😉" "😊" "😋" "😎" "😍" "😘" "😗" "😙" "😚" "🙂" "🤗" "🤩" "🤔" "🤨" "😐" "😑" "😶" "🙄" "😏" "😣" "😥" "😮" "🤐" "😯" "😪" "😫" "😴" "😌" "😛" "😜" "😝" "🤤" "😒" "😓" "😔" "😕" "🙃" "🤑" "😲" "☹️" "🙁" "😖" "😞" "😟" "😤" "😢" "😭" "😦" "😧" "😨" "😩" "🤯" "😬" "😰" "😱" "🥵" "🥶" "😳" "🤪" "😵" "😡" "😠" "🤬" "😷" "🤒" "🤕" "🤢" "🤮" "🤧" "😇" "🤠" "🤡" "🥳" "🥴" "🥺" "🤥" "🤫" "🤭" "🧐" "🤓" "😈" "👿" "👹" "👺" "💀" "👻" "👽" "🤖" "💩" "😺" "😸" "😹" "😻" "😼" "😽" "🙀" "😿" "😾")
emoji=${emojis[$RANDOM % ${#emojis[@]}]}
echo "emoji: \"$emoji\"" >> articles/${slug}.md

echo "type: tech" >> articles/${slug}.md
echo "topics: []" >> articles/${slug}.md
echo "published: false" >> articles/${slug}.md
echo "---" >> articles/${slug}.md

# `articles/${slug}` のブランチを作成する
git switch -c articles/${slug}

# 新規作成したブランチでコミットする
git add articles/${slug}.md
git commit -m "新規記事追加: ${slug}"

# pushする
git push -u origin articles/${slug}

# gh cliを使ってPull Requestを作成する
gh pr create --title "新規記事: ${title}" --body "この PR は新規記事 ${title} を追加します。" --base main --head articles/${slug} --draft