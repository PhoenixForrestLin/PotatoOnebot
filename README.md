# flutter_package_onebot

一个用于 Flutter 应用的 OneBot WebSocket 客户端库，纯 Dart 实现，方便与 OneBot 服务端进行交互。

## 特性

- 支持通过 WebSocket 与 OneBot 服务端通信
- 支持发送动作、接收事件和响应
- 纯 Dart 实现，无需依赖其他语言 SDK
- 适合自定义扩展和二次开发


## 快速开始

```dart
import 'package:flutter_package_onebot/flutter_package_onebot.dart';

void main() async {
  final onebot = await OneBotWebSocket.connect(
    url: 'ws://your-onebot-server/ws',
    token: 'your-access-token', // 可选
  );

  // 发送动作
  onebot.post(
    data: Active(
      action: 'send_message',
      params: {'user_id': '123456', 'message': 'Hello!'},
    ),
  );

  // 关闭连接
  onebot.close();
}
```

## 注意事项

- 目前仅支持正向 WebSocket 连接，不支持 HTTP。
- 该库为基础实现，部分功能可能不完善，欢迎 issue 和 PR。
- 还未经过充分测试，生产环境请谨慎使用。

## 贡献

欢迎提交 issue 和 pull request！