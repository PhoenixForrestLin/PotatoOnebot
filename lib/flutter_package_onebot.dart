import 'dart:async';
import 'dart:collection';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

/* * OneBot WebSocket连接类
 * 
 * 这是一个用于应用端使用WebSocket连接OneBot实现的类，提供了发送动作、接收事件和响应等基础功能。
 * 
 * 纯dart实现，无需使用python或其他语言的OneBot SDK。
 * 
 * 希望这个库能帮助你更方便地与OneBot服务端进行交互，专注于业务逻辑而不是底层实现。
 * 
 * 目前仅支持正向 WebSocket 连接，不支持 HTTP。
 * 
 * 该库为基础实现，部分功能可能不完善，欢迎 issue 和 PR。
 * 
 * 还未经过充分测试，生产环境请谨慎使用。
 * 
 * 如果你发现了bug或有任何建议，请在GitHub上提交issue或pull request。
 * 
 * @author: Phoenix Forrest Lin
 * @version: 0.1.0
 * @date: 2025-7-12
 */

/// Self类，用于表示OneBot的机器人信息
class Self{
  final String platform;
  final String userid;
  Self({
    required this.platform,
    required this.userid,
  });
}

/// 动作类，用于表示OneBot的动作
class Active{
  final String action;
  final Map<String,dynamic> params;
  final String? echo;
  final Self? self;
  Active({required this.action, required this.params, this.echo, this.self});
}

/// 响应类，用于表示OneBot的响应
class ActiveResponse{
  final String satus;
  final int retcode;
  final dynamic data;
  final String message; 
  final String? echo;
  ActiveResponse({required this.satus, required this.retcode, this.data,this.message='', this.echo});
}

/// 事件类，用于表示OneBot事件
class Event{
  final String id;
  final double time;
  final String type;
  final String detailtype;
  final String subtype;
  final Self? self;
  final Map<String, dynamic>? data;
  Event({
    required this.id,
    this.self,
    required this.time,
    required this.type,
    required this.detailtype,
    required this.subtype,
    this.data,
  });
}

/// 消息类，用于表示OneBot消息
class Message {
  final String type;
  final dynamic data;
  Message({
    required this.type,
    required this.data,
  });
}

/// 将Map转换为JSON字符串
String toJson(Map<String, dynamic> data) {
  String jsonString = '{';
  data.forEach((key, value) {
    if (value is String) {
      jsonString += '"$key":"$value",';
    } else if (value is Map<String, dynamic>) {
      jsonString += '"$key":${toJson(value)},';
    } else if (value is List) {
      jsonString += '"$key":${value.toString()},';
    } else {
      // ignore: unnecessary_brace_in_string_interps
      jsonString += '"$key":${value},';
    }
  });
  jsonString+= '}';
  return jsonString;
}

/// 将JSON字符串或其他数据转换为Map或元素
dynamic fromJson(String json) {
  if (json.startsWith('{') && json.endsWith('}')) {
    return _fromJson(json);
  } else {
    return _fromPartJson(json); // 处理非对象的JSON片段
  }
}

/// 这是一个私有函数，用于将JSON字符串转换为Map
Map<String, dynamic> _fromJson(String json) {
  Map<String, dynamic> data = {};
  for(int i=1;i<json.length-1;i++){// 从1开始，跳过开头的{,结尾跳过}
    final char = json[i];
    if (char == ' ') continue; // 跳过空格
    if (char == '"') {
      final end = json.indexOf('"', i + 1);
      final key = json.substring(i + 1, end);
      i = end + 1; // 跳过结束的引号
      final valueStart = json.indexOf(':', i) + 1;
      final valueEnd = json.indexOf(',', valueStart);
      final value = json.substring(valueStart, valueEnd == -1 ? json.length : valueEnd).trim();
      data[key] = _fromPartJson(value); // 解析值
      i = valueEnd == -1 ? json.length : valueEnd; // 跳过逗号
    }
  }
  return data;
}

//这是一个递归解析JSON片段的私有函数
dynamic _fromPartJson (String value) {
  if (value.startsWith('"') && value.endsWith('"')) {
        return value.substring(1, value.length - 1); // 去掉引号
      } else if (value.startsWith('{') && value.endsWith('}')) {
        return _fromJson(value); // 递归解析嵌套的JSON对象
      } else if (value.startsWith('[') && value.endsWith(']')) {
        final list = value.substring(1, value.length - 1).split(',').map((e) => e.trim()).toList(); // 解析数组
        List<dynamic> result = [];
        for (var item in list) {
          result.add(_fromPartJson(item)); // 递归解析数组中的每个元素
        }
        return result; // 返回解析后的数组
      } else if (value == 'true') {
        return true;
      } else if (value == 'false') {
        return false;
      } else {
        return num.tryParse(value) ?? value; // 尝试转换为数字
      }
}

///一个用于客户端的OneBot WebSocket连接类
class OneBotWebSocket {

  /// WebSocket连接的通道
  final WebSocketChannel channel;

  /// 重连间隔时间，单位为毫秒，默认3000毫秒
  /// 
  /// 目前并没有做重连机制，这玩意没啥用
  final int reconnectInterval;

  //final String username;
  //final String impl; 
  //刚开始写的时候把客户端和服务端弄混了，目前没啥用（也许之后扩展客户端作为ws服务器连接会有用？）

  ///这是你的access_token
  final String? token;

  /// TO_DO:支持的动作列表
  /// 
  /// PS: 他在设计中其实是final类型的，但我不想在构造函数里初始化
  //List<String>? supportedactions;

  /// 用于生成echo的消息计数器，记录你发了多少条信息，到达int最大值后会重置为1
  int messagesum=1;

  /// 用于存储echo和action的映射关系
  /// 
  /// 跟目前未实现的一个todo有关，没用
  Map<String,String> echoMap= {};

  /// 用于存储事件的队列 
  // To_Do: 用一个provider包裹它
  Queue<Event> eventQueue = Queue<Event>();

  /// 用于存储响应的队列
  // To_Do: 用一个provider包裹它
  Queue<ActiveResponse> responseQueue = Queue<ActiveResponse>();

  /// 私有构造函数，用于创建OneBotWebSocket实例
  OneBotWebSocket._({
    required this.channel,
    required this.reconnectInterval,
    //required this.username,
    //required this.impl,
    this.token,
    //required this.supportedactions,
  });

  /// 异步工厂构造函数，用于初始化OneBotWebSocket
  Future<OneBotWebSocket> connect({
    required String url,
    //required String useragent,
    //required String impl,
    String? token,
    int? reconnect,
  }) async {
    final channel = WebSocketChannel.connect(Uri.parse(url));
    await channel.ready;
    channel.stream.listen(
      (message) {
        _messagereceive(message);
      },
    );
    return OneBotWebSocket._(
      channel: channel,
      reconnectInterval: reconnect ?? 3000,
      //username: useragent,
      token: token,
      //impl: impl,
    );
  }

  /// 发送一个动作请求
  void post({required Active data}) {
    final message = {
      'action': data.action,
      'params': data.params,
      if( data.echo != null) 'echo': data.echo,
      if (data.self != null) 'self': data.self,
    };
    channel.sink.add(toJson(message));
  }

  // ignore: slash_for_doc_comments
  /** 
  TO_DO:初始化支持的动作列表（仅发送请求）
  void _initSupportedActions() {
    final echo = _makeecho();
    echoMap.addAll({echo:"get_supported_actions"});
    post(
      data: Active(
        action: 'get_supported_actions',
        params: {},
        echo: _makeecho(),
      ),
    );
  }
  **/

  /// 处理接收到的消息,push至消息队列中
  void _messagereceive(String message) {
    Map<String, dynamic> data = fromJson(message);
    if(data["id"] != null) {
      // 处理事件
      final event = Event(
        id: data["id"],
        time: data["time"]?.toDouble() ?? DateTime.now().millisecondsSinceEpoch.toDouble(),
        type: data["type"],
        detailtype: data["detail_type"],
        subtype: data["sub_type"],
        self: data["self"] != null ? Self(
          platform: data["self"]["platform"],
          userid: data["self"]["user_id"],
        ) : null,
        data: data["data"],
      );
      eventQueue.add(event);
    } else if (data['status'] != null) {
      // 处理响应
      final response = ActiveResponse(
        satus: data['status'],
        retcode: data['retcode'],
        data: data['data'],
        message: data['message'] ?? '',
        echo: data['echo'],
      );
      responseQueue.add(response);
    }
  }

  ///生成一个echo，格式为${DateTime.now().millisecondsSinceEpoch}-${messagesum++}
  ///
  // ignore: unused_element
  String _makeecho(){
    final now= DateTime.now();
    if (messagesum >= (1<<64)-1) {
      messagesum = 1;
    }
    final echo = '${now.millisecondsSinceEpoch}-${messagesum++}';
    return echo;
  }

  /// 关闭WebSocket连接
  /// 
  /// 结束之前记得调用一下
  void close() {
    channel.sink.close(status.normalClosure);
  }
}