---
title: "HAIRを入れたらHome Assistantがユニバーサルリモコンプラットフォームに化けた話"
emoji: "📡"
type: "tech"
topics: ["HomeAssistant", "ESPHome", "infrared", "IoT"]
published: false
---
はいどーも、はおりんです！

家の中の「赤外線リモコンでしか操作できない家電」、みなさんどうしてますか。扇風機とか、照明とか、ちょっと古いテレビとか

うちではESPHomeで赤外線を読み書きして、Home Assistantから操作できるようにしていました。していたんですが、その運用がまあまあしんどかった。そこに **HAIR** がやってきて、全部GUIで管理できるようになったら、めちゃめちゃ楽になって、気づいたらHome Assistantが本格的なユニバーサルリモコンプラットフォームに化けていた、という話です

<!-- TODO: 使っているESPHomeデバイス（ボード名・赤外線LED/受光モジュール）を書く -->

---

## 以前のやり方：全部ESPHomeのconfigに直書き

### 1. まず赤外線コードを読み取る

ESPHomeの `remote_receiver` に `dump: all` を付けておくと、受光したコードがログに流れてきます

```yaml
remote_receiver:
  pin:
    number: GPIO8
    inverted: true
  dump: all
```

扇風機のリモコンをESPHomeデバイスに向けてボタンを押すと、ログにこんな感じのものが出る

```
[I][remote.nec:xxx]: Received NEC: address=0x1234, command=0x5678
```

これをボタンひとつずつ、押してはログを見て、メモしていく

### 2. 読み取ったコードでボタンをたくさん作る

メモしたコードを、今度は `remote_transmitter` で送るボタンとしてconfigに書いていきます

```yaml
remote_transmitter:
  pin: GPIO9
  carrier_duty_percent: 50%

button:
  - platform: template
    name: "扇風機 電源"
    on_press:
      - remote_transmitter.transmit_nec:
          address: 0x1234
          command: 0x5678
  - platform: template
    name: "扇風機 風量"
    on_press:
      - remote_transmitter.transmit_nec:
          address: 0x1234
          command: 0x5679
  - platform: template
    name: "扇風機 首振り"
    on_press:
      - remote_transmitter.transmit_nec:
          address: 0x1234
          command: 0x567A
  # ……これがリモコンのボタンの数だけ続く
```

<!-- TODO: 実際の扇風機のプロトコル（NEC? raw?）とボタン数に合わせて調整 -->

ESPHomeのデバイスの中にボタンがずらーっと並び、Home Assistant側ではそのボタンを叩いて扇風機を操作します。さらにHome Assistantの「扇風機」エンティティとして扱いたかったので、テンプレートのfanを作って、オン/オフや風量の変更でこのボタンを押すようにしていました

<!-- TODO: HA側の扇風機エンティティをどう作っていたか（template fan など）を補足 -->

### 3. 使っていないテレビのリモコンを「入力デバイス」にする

ここからがちょっと楽しいところで、家に転がっていた**使っていないテレビのリモコン**を、Home Assistantの物理リモコンとして使おうと考えました。ボタンがいっぱいあるし、電池も長持ちするし、なにより手に馴染む

これも同じくまずコードを読み取って、今度は `binary_sensor` として全ボタン分をconfigに作ります

```yaml
binary_sensor:
  - platform: remote_receiver
    name: "TVリモコン 1"
    nec:
      address: 0x4321
      command: 0x0001
    filters:
      - delayed_off: 200ms
  - platform: remote_receiver
    name: "TVリモコン 2"
    nec:
      address: 0x4321
      command: 0x0002
    filters:
      - delayed_off: 200ms
  # ……これもボタンの数だけ続く
```

Home Assistant側では、このbinary_sensorが `on` になったことをトリガーにオートメーションを組む。「1を押したらリビングの電気」「2を押したら扇風機」みたいな感じです

### 何がしんどかったか

動くことは動くんです。ただ

- **コードを1個追加するたびにconfigを書いてビルドしてOTAで焼き直し**。ESPHomeのビルド、地味に時間かかる
- 読み取りはログを眺めながら「今のどのボタンだっけ」と手でメモする作業
- ボタン数×リモコン数でyamlがどんどん長くなる
- どのbinary_sensorがどのオートメーションに紐付いているのか、configとHAを行ったり来たりしないとわからない

「赤外線コードがファームウェアに焼き込まれている」構造そのものが、運用の重さになっていました

---

## HAIRがやってきた

Home Assistantは2026.4で、コアに **Infrared** というエンティティプラットフォームが入りました。ESPHome側には **IR/RF Proxy**（`ir_rf_proxy`）コンポーネントができて、ESPHomeデバイスを「赤外線を送受信するだけのプロキシ」としてHome Assistantに見せられるようになった。Bluetoothプロキシの赤外線版、というイメージです

ただ、このInfraredプラットフォームは「ビルディングブロック」で、それ単体では「このコードを送るボタン」みたいなものは作ってくれません。そこで出てくるのが **[HAIR](https://github.com/DAB-LABS/HAIR)** です

HAIRはDAB-LABSさんが作っている、HACSで入れられるカスタム統合で、Home Assistant 2026.6以降のinfraredプラットフォームの上で動く「赤外線デバイスの管理パネル」です。サイドバーにHAIRのパネルが生えて、そこで

- リモコンを受光機に向けて押すと、**Sniffer** タブにリアルタイムで信号が出てくる
- 出てきた信号を選んで **Make a Device** すると、ボタンエンティティ付きのデバイスができる
- 信号から**トリガー**（eventエンティティ）を作れる
- 手持ちのリモコンを **Remote** として登録すると、そのリモコン自体がHAのデバイスになる

ということが、全部GUIでできます。YAMLは書きません

---

## ESPHome側の変更は一回だけ

ESPHome側は、既存の `remote_transmitter` / `remote_receiver` をinfraredプラットフォームに登録する設定を足すだけです

```yaml
infrared:
  - platform: ir_rf_proxy
    name: IR Emitter
    id: ir_proxy_tx
    remote_transmitter_id: ir_tx
  - platform: ir_rf_proxy
    name: IR Receiver
    id: ir_proxy_rx
    receiver_frequency: 38kHz
    remote_receiver_id: ir_rx
```

そして、あのずらーっと並んでいた `button` と `binary_sensor` は**全部消しました**。気持ちいい

これを最後に焼けば、以降はコードを追加しても焼き直しは不要です。ESPHomeデバイスはただの「赤外線の耳と口」になって、何を送るか・何を聞いたら何をするかは全部Home Assistant側で持つ構造になりました

<!-- TODO: 実際のyamlに置き換え（idle / clock_resolution などを調整したならそれも） -->

---

## 扇風機を登録する

1. HAIRのパネルでSnifferタブを開く
2. 扇風機のリモコンを受光機に向けて、ボタンを何回か押す（新しいリモコンは3回くらい押すとカードとして出てくる）
3. 出てきた信号に名前を付けて、**USE** → **Make a Device**
4. できたデバイスのボタンを押すと、扇風機が反応する

さらにデバイスの種類をFanにして、各コマンドを **ACTIONS** で `turn_on` や風量の操作に割り当てると、HAの `fan` エンティティとして扱えるようになります。以前テンプレートのfanで頑張っていたところが、これで置き換わりました

<!-- TODO: スクショ（Sniffer / デバイス画面） -->

---

## テレビのリモコンを「Home Assistantのリモコン」にする

使っていないテレビのリモコンも同じくSnifferで拾って、今度は **Make a Remote** にします

Remoteにすると、そのリモコンがHome Assistantのデバイスとして登録されて、オートメーションエディタの「デバイス」トリガーにボタン名がそのまま出てくる。さらに **Last pressed** というeventエンティティが生えていて、「どのボタンが押されたか」をイベントタイプとして受け取れるので、オートメーション1本で全ボタンを捌くこともできます

以前はbinary_sensorをボタンの数だけconfigに書いていたのが、リモコンを向けてポチポチ押して、GUIでトリガーにするだけになりました

<!-- TODO: 実際に組んだオートメーションの例（YAML or スクショ） -->

---

## ユニバーサルリモコンプラットフォームに化けた

ここまで来て気づいたんですが、これもう**Home Assistantがユニバーサルリモコンそのもの**なんですよね

- 赤外線で操作する家電は、全部HAのデバイス／エンティティになる（送信側）
- 手元にある赤外線リモコンは、どれでもHAの入力デバイスになる（受信側）
- その間はHAのオートメーションで自由につなげる

テレビのリモコンで扇風機を操作してもいいし、扇風機のリモコンで照明をつけてもいい。赤外線で操作できないMatterやZigbeeのデバイスを、赤外線リモコンから操作することもできる。HAIRには「RemoteをDeviceにピン留めすると、リモコンで押したボタンをそのままDeviceに中継する」という機能まであって、まさにリモコンのハブです

しかもコードの追加や変更で、ESPHomeを焼き直す必要がない。この「思いついたらすぐ登録できる」軽さが、ユニバーサルリモコン化を一気に現実的にしてくれました

---

## おわりに

ESPHomeのconfigにIRコードを直書きしていた頃は、「動くけど、増やすのが面倒」という状態でした。HAIRに移行してGUIで管理するようにしたら、コードを読むのもトリガーを作るのもHome Assistantの画面の中で完結して、めちゃめちゃ楽になった

家に眠っている使っていないリモコン、捨てずに取っておくと、いい入力デバイスになりますよ

以上、赤外線まみれの部屋からはおりんがお伝えしましたー！

参考:
- [HAIR (DAB-LABS/HAIR)](https://github.com/DAB-LABS/HAIR)
- [2026.4: Infrared never left the chat - Home Assistant](https://www.home-assistant.io/blog/2026/04/01/release-20264)
- [Infrared - Home Assistant](https://www.home-assistant.io/integrations/infrared)
- [IR/RF Proxy - ESPHome](https://esphome.io/components/ir_rf_proxy)
