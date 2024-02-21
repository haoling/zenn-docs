---
title: "FastAPIを使って、ChatGPTのプラグインを開発する"
emoji: "🤖"
type: "tech"
topics: ["ChatGPT"] # タグ。["markdown", "rust", "aws"]のように指定する
published: false # 公開設定（falseにすると下書き）
---
# 概要
ChatGPTは、出回っている多数のプラグインを活用することができます。
しかし、自分自身でプラグインを開発しようと思うと、技術的なハードルや時間的なコストが大きくなりがちです。
この投稿では、PythonのFastAPIモジュールを使用して、簡単なプラグイン開発をする手順を説明します。

# この投稿で開発するプラグイン
外部に用意された、今後7日間の予定が含まれたJSONファイルを取得して、AIに渡すプラグインです。
AI（ChatGPT）は、スケジュールを確認する必要があるときに、このプラグインを呼び出すことができます。

# 外部に用意されたJSON
Googleカレンダーから取得できるJSONを、不要なフィールドを削除して軽量化しました。
不要な情報の削除は、ハルシネーションの抑止・トークン使用量の低減・生成速度の向上のすべてに良い効果があります。
```json
{
  "data": [
    {
      "kind": "calendar#event",
      "status": "confirmed",
      "htmlLink": "https://www.google.com/calendar/event?eid=xxxxxxxxxxxx",
      "summary": "用賀スタジオ見学",
      "start": {
        "dateTime": "2024-02-21T10:00:00+09:00",
        "timeZone": "Asia/Tokyo"
      },
      "end": {
        "dateTime": "2024-02-21T13:00:00+09:00",
        "timeZone": "Asia/Tokyo"
      }
    },
    {
      "kind": "calendar#event",
      "status": "confirmed",
      "htmlLink": "https://www.google.com/calendar/event?eid=xxxxxxxxxxxx",
      "summary": "出社",
      "start": {
        "dateTime": "2024-02-21T10:45:00+09:00",
        "timeZone": "Asia/Tokyo"
      },
      "end": {
        "dateTime": "2024-02-21T19:30:00+09:00",
        "timeZone": "Asia/Tokyo"
      }
    }
  ]
}
```

# 期待される動作
LibreChatでgpt-4-0125-previewを使用した場合の実動例です。
```plaintext
>> User:
来週の火曜日は、リモートワークだっけ？


>> GPT-4:
:::plugin:::
来週の火曜日（2月27日）は、午前中は出社の予定があり、10:45から15:00までとなっています。午後は「午後休」となっており、リモートワークの予定はありません。
```
実際に2/27は出社ののち通院の予定となっており、リモートワークではありません。
午後休の予定であることも教えてくれています。
前出のサンプルJSONでは2/27の予定までは見えていませんが、実際には7日間分のスケジュールをJSON出力しています。

# 実際のコード
```python
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import uvicorn
import requests

# 返却されるデータ（JSONの中身）の構造を、Pythonの型として定義
class EventDate(BaseModel):
    date: str
class Event(BaseModel):
    kind: str
    status: str
    htmlLink: str
    summary: str
    description: str = None
    start: EventDate
    end: EventDate
class ResponseModel(BaseModel):
    data: list[Event]

# FastAPIのインスタンスを生成
app = FastAPI(
    title="GoogleCalendarEvents",
    description="Googleカレンダーから、未来7日間の予定を取得するAPIです。",
    servers=[
        {"url": "http://localhost:8081/", "description": "local"},
    ],
)

# LibreChatのプラグインシステムがOpenAPIの3.0.2までしかサポートしていないため、強制的に指定する
app.openapi_version = "3.0.2"

# /.well-known ディレクトリは静的なファイルとして配信する
app.mount("/.well-known", StaticFiles(directory=".well-known"), name="well-known")

# 外部からJSONを取得してくるロジック部分
@app.get("/events", summary="未来7日間の予定を取得する", response_model=ResponseModel)
async def main_logic():
    res = requests.get("http://localhost:8080/my-calendar.json")
    json_compatible_item_data = jsonable_encoder(res.json())
    return JSONResponse(content=json_compatible_item_data)

# 8081ポートでListenする
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8081, log_level="debug")
```
実際の処理は main_logic の部分で、my-calendar.jsonを取得しているに過ぎません。
response_model=ResponseModel の指定で、返されるデータの型を明示しています。この型の情報は後述するopenapi.jsonに記載されます。

# ai-plugin.json
このファイルは手で書く必要がありますが、難しいものではありません。
```json
{
  "schema_version": "v1",
  "name_for_model": "tools-my-calendar",
  "name_for_human": "tools-my-calendar",
  "description_for_model": "Googleカレンダーから、未来7日間の予定を取得します。",
  "description_for_human": "tools-my-calendar",
  "auth" : {
    "type":"none"
  },
  "api":{
    "type": "openapi",
    "url": "http://localhost:8081/openapi.json"
  }
}
```
しかしここで、openapi.jsonという見慣れないファイルが出てきます。
このファイルに、リクエストや応答の形式を書いておかねばならず、非常に手間です。
しかしFastAPIは、この、openapi.jsonを自動的に生成してくれます。

# 実際に生成されたopenapi.json
これは実際に生成されたものです。
自動的に生成されるので、このファイルを手書きする必要はありません。
```json
{
  "openapi": "3.0.2",
  "info": {
    "title": "GoogleCalendarEvents",
    "description": "Googleカレンダーから、未来7日間の予定を取得するAPIです。",
    "version": "0.1.0"
  },
  "servers": [
    {
      "url": "http://localhost:8081/",
      "description": "local"
    }
  ],
  "paths": {
    "/events": {
      "get": {
        "summary": "未来7日間の予定を取得する",
        "operationId": "main_logic_events_get",
        "responses": {
          "200": {
            "description": "Successful Response",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/ResponseModel"
                }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "Event": {
        "properties": {
          "kind": {
            "type": "string",
            "title": "Kind"
          },
          "status": {
            "type": "string",
            "title": "Status"
          },
          "htmlLink": {
            "type": "string",
            "title": "Htmllink"
          },
          "summary": {
            "type": "string",
            "title": "Summary"
          },
          "description": {
            "type": "string",
            "title": "Description"
          },
          "start": {
            "$ref": "#/components/schemas/EventDate"
          },
          "end": {
            "$ref": "#/components/schemas/EventDate"
          }
        },
        "type": "object",
        "required": [
          "kind",
          "status",
          "htmlLink",
          "summary",
          "start",
          "end"
        ],
        "title": "Event"
      },
      "EventDate": {
        "properties": {
          "date": {
            "type": "string",
            "title": "Date"
          }
        },
        "type": "object",
        "required": [
          "date"
        ],
        "title": "EventDate"
      },
      "ResponseModel": {
        "properties": {
          "data": {
            "items": {
              "$ref": "#/components/schemas/Event"
            },
            "type": "array",
            "title": "Data"
          }
        },
        "type": "object",
        "required": [
          "data"
        ],
        "title": "ResponseModel"
      }
    }
  }
}
```

# まとめ
FastAPIを利用することで、GETやPOSTメソッド、さらには複数の機能をサポートしたプラグインまで、比較的簡単に開発することが出来ます。
みなさんもChatGPTに機能を追加して、快適な未来をお過ごしください。