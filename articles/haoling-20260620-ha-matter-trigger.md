---
title: "HomeAssistantでMatterのボタンデバイスのイベントをトリガーにするメモ"
emoji: "🧵"
type: "tech"
topics: ["HomeAssistant", "Matter"]
published: true
---
はいどーも、はおりんです！

これはメモ記事です。

# TL;DR
トリガー: stateの変更(any)
条件: イベントタイプ [multi_press_1, multi_press_2, multi_press_3, long_press, long_release]

# Matterのボタンデバイスの「イベント」
Home Assistantで「ボタンを長押ししたら何かをする」というオートメーションを組みたい時に、トリガーをどうすれば良いか、わからなかったんですよ。
ボタンエンティティを指定しても変化前と変化後の状態の選択肢には「利用不可、不明、任意の状態」の3択しか出てこない。デバイスのトリガーでも「バッテリー状態の変化」とか「ファームウェアが更新可能」とかしか出てこない。
開発者ツールでイベントフィルタを "*" にしてリッスンしてボタンを押しても、「状態が変化した」系イベントしか観測されない。

状態変化した際にはこのようなイベントが発行される。

```yaml
event_type: state_changed
data:
  entity_id: event.bilresahoirubai_hotan_6
  old_state:
    entity_id: event.bilresahoirubai_hotan_6
    state: "2026-06-14T04:52:48.750+00:00"
    attributes:
      event_types:
        - multi_press_1
        - multi_press_2
        - multi_press_3
        - long_press
        - long_release
      event_type: multi_press_1
      previousPosition: 1
      totalNumberOfPressesCounted: 1
      device_class: button
      friendly_name: 2-push
    last_changed: "2026-06-14T16:13:06.518585+00:00"
    last_reported: "2026-06-14T16:13:06.518585+00:00"
    last_updated: "2026-06-14T16:13:06.518585+00:00"
    context:
      id: 01KV3EH02PNJEX9GAH1S4XN2XB
      parent_id: null
      user_id: null
  new_state:
    entity_id: event.bilresahoirubai_hotan_6
    state: "2026-06-20T05:52:35.923+00:00"
    attributes:
      event_types:
        - multi_press_1
        - multi_press_2
        - multi_press_3
        - long_press
        - long_release
      event_type: multi_press_1
      previousPosition: 1
      totalNumberOfPressesCounted: 1
      device_class: button
      friendly_name: 2-push
    last_changed: "2026-06-20T05:52:35.923505+00:00"
    last_reported: "2026-06-20T05:52:35.923505+00:00"
    last_updated: "2026-06-20T05:52:35.923505+00:00"
    context:
      id: 01KVHSD42KW2AVYJ488MAE22AY
      parent_id: null
      user_id: null
origin: LOCAL
time_fired: "2026-06-20T05:52:35.923505+00:00"
context:
  id: 01KVHSD42KW2AVYJ488MAE22AY
  parent_id: null
  user_id: null
```

stateにはタイムスタンプが格納されている。
new_stateとnew_stateのevent_typeの値は同じだが、同じであっても「直近のイベントのタイプ」が、どうやら記録されているらしい。
つまり「なんでもいいから状態が変化した」というトリガーでイベントを拾って、イベント発火後の条件で「data.new_state.attributes.event_type == multi_press_1」という条件で絞ることで、「1回押した」イベントが拾えるようだ。
例えば長押しなら、こう。

```yaml
triggers:
  - trigger: state
    entity_id:
      - event.bilresahoirubai_hotan_3
conditions:
  - condition: state
    entity_id: event.bilresahoirubai_hotan_3
    state:
      - long_press
    attribute: event_type
```