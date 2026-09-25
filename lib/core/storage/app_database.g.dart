// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ChatMessagesTable extends ChatMessages
    with TableInfo<$ChatMessagesTable, ChatMessageRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionKeyMeta = const VerificationMeta(
    'sessionKey',
  );
  @override
  late final GeneratedColumn<String> sessionKey = GeneratedColumn<String>(
    'session_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uinMeta = const VerificationMeta('uin');
  @override
  late final GeneratedColumn<int> uin = GeneratedColumn<int>(
    'uin',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeMeta = const VerificationMeta('time');
  @override
  late final GeneratedColumn<int> time = GeneratedColumn<int>(
    'time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _extendDataMeta = const VerificationMeta(
    'extendData',
  );
  @override
  late final GeneratedColumn<String> extendData = GeneratedColumn<String>(
    'extend_data',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isSuccessMeta = const VerificationMeta(
    'isSuccess',
  );
  @override
  late final GeneratedColumn<bool> isSuccess = GeneratedColumn<bool>(
    'is_success',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_success" IN (0, 1))',
    ),
  );
  static const VerificationMeta _notTimeMeta = const VerificationMeta(
    'notTime',
  );
  @override
  late final GeneratedColumn<int> notTime = GeneratedColumn<int>(
    'not_time',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _srcUserVersionMeta = const VerificationMeta(
    'srcUserVersion',
  );
  @override
  late final GeneratedColumn<String> srcUserVersion = GeneratedColumn<String>(
    'src_user_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bubbleMeta = const VerificationMeta('bubble');
  @override
  late final GeneratedColumn<String> bubble = GeneratedColumn<String>(
    'bubble',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _interCodeMeta = const VerificationMeta(
    'interCode',
  );
  @override
  late final GeneratedColumn<String> interCode = GeneratedColumn<String>(
    'inter_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<int> groupId = GeneratedColumn<int>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isSystemMsgMeta = const VerificationMeta(
    'isSystemMsg',
  );
  @override
  late final GeneratedColumn<bool> isSystemMsg = GeneratedColumn<bool>(
    'is_system_msg',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_system_msg" IN (0, 1))',
    ),
  );
  static const VerificationMeta _isTimeMeta = const VerificationMeta('isTime');
  @override
  late final GeneratedColumn<bool> isTime = GeneratedColumn<bool>(
    'is_time',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_time" IN (0, 1))',
    ),
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _msgTypeMeta = const VerificationMeta(
    'msgType',
  );
  @override
  late final GeneratedColumn<String> msgType = GeneratedColumn<String>(
    'msg_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('text'),
  );
  static const VerificationMeta _ownerUinMeta = const VerificationMeta(
    'ownerUin',
  );
  @override
  late final GeneratedColumn<int> ownerUin = GeneratedColumn<int>(
    'owner_uin',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    content,
    sessionKey,
    uin,
    time,
    extendData,
    isSuccess,
    notTime,
    srcUserVersion,
    bubble,
    interCode,
    groupId,
    isSystemMsg,
    isTime,
    direction,
    msgType,
    ownerUin,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatMessageRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('session_key')) {
      context.handle(
        _sessionKeyMeta,
        sessionKey.isAcceptableOrUnknown(data['session_key']!, _sessionKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionKeyMeta);
    }
    if (data.containsKey('uin')) {
      context.handle(
        _uinMeta,
        uin.isAcceptableOrUnknown(data['uin']!, _uinMeta),
      );
    } else if (isInserting) {
      context.missing(_uinMeta);
    }
    if (data.containsKey('time')) {
      context.handle(
        _timeMeta,
        time.isAcceptableOrUnknown(data['time']!, _timeMeta),
      );
    } else if (isInserting) {
      context.missing(_timeMeta);
    }
    if (data.containsKey('extend_data')) {
      context.handle(
        _extendDataMeta,
        extendData.isAcceptableOrUnknown(data['extend_data']!, _extendDataMeta),
      );
    }
    if (data.containsKey('is_success')) {
      context.handle(
        _isSuccessMeta,
        isSuccess.isAcceptableOrUnknown(data['is_success']!, _isSuccessMeta),
      );
    } else if (isInserting) {
      context.missing(_isSuccessMeta);
    }
    if (data.containsKey('not_time')) {
      context.handle(
        _notTimeMeta,
        notTime.isAcceptableOrUnknown(data['not_time']!, _notTimeMeta),
      );
    }
    if (data.containsKey('src_user_version')) {
      context.handle(
        _srcUserVersionMeta,
        srcUserVersion.isAcceptableOrUnknown(
          data['src_user_version']!,
          _srcUserVersionMeta,
        ),
      );
    }
    if (data.containsKey('bubble')) {
      context.handle(
        _bubbleMeta,
        bubble.isAcceptableOrUnknown(data['bubble']!, _bubbleMeta),
      );
    }
    if (data.containsKey('inter_code')) {
      context.handle(
        _interCodeMeta,
        interCode.isAcceptableOrUnknown(data['inter_code']!, _interCodeMeta),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('is_system_msg')) {
      context.handle(
        _isSystemMsgMeta,
        isSystemMsg.isAcceptableOrUnknown(
          data['is_system_msg']!,
          _isSystemMsgMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_isSystemMsgMeta);
    }
    if (data.containsKey('is_time')) {
      context.handle(
        _isTimeMeta,
        isTime.isAcceptableOrUnknown(data['is_time']!, _isTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_isTimeMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('msg_type')) {
      context.handle(
        _msgTypeMeta,
        msgType.isAcceptableOrUnknown(data['msg_type']!, _msgTypeMeta),
      );
    }
    if (data.containsKey('owner_uin')) {
      context.handle(
        _ownerUinMeta,
        ownerUin.isAcceptableOrUnknown(data['owner_uin']!, _ownerUinMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatMessageRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessageRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      sessionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_key'],
      )!,
      uin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}uin'],
      )!,
      time: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time'],
      )!,
      extendData: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extend_data'],
      ),
      isSuccess: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_success'],
      )!,
      notTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}not_time'],
      ),
      srcUserVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}src_user_version'],
      ),
      bubble: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bubble'],
      ),
      interCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inter_code'],
      ),
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}group_id'],
      ),
      isSystemMsg: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_system_msg'],
      )!,
      isTime: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_time'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      msgType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}msg_type'],
      )!,
      ownerUin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}owner_uin'],
      )!,
    );
  }

  @override
  $ChatMessagesTable createAlias(String alias) {
    return $ChatMessagesTable(attachedDatabase, alias);
  }
}

class ChatMessageRecord extends DataClass
    implements Insertable<ChatMessageRecord> {
  final int id;
  final String content;
  final String sessionKey;
  final int uin;
  final int time;
  final String? extendData;
  final bool isSuccess;
  final int? notTime;
  final String? srcUserVersion;
  final String? bubble;
  final String? interCode;
  final int? groupId;
  final bool isSystemMsg;
  final bool isTime;
  final String direction;
  final String msgType;

  /// 账号归属（本地多账号数据隔离）：0=旧数据（首登收养）。
  final int ownerUin;
  const ChatMessageRecord({
    required this.id,
    required this.content,
    required this.sessionKey,
    required this.uin,
    required this.time,
    this.extendData,
    required this.isSuccess,
    this.notTime,
    this.srcUserVersion,
    this.bubble,
    this.interCode,
    this.groupId,
    required this.isSystemMsg,
    required this.isTime,
    required this.direction,
    required this.msgType,
    required this.ownerUin,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['content'] = Variable<String>(content);
    map['session_key'] = Variable<String>(sessionKey);
    map['uin'] = Variable<int>(uin);
    map['time'] = Variable<int>(time);
    if (!nullToAbsent || extendData != null) {
      map['extend_data'] = Variable<String>(extendData);
    }
    map['is_success'] = Variable<bool>(isSuccess);
    if (!nullToAbsent || notTime != null) {
      map['not_time'] = Variable<int>(notTime);
    }
    if (!nullToAbsent || srcUserVersion != null) {
      map['src_user_version'] = Variable<String>(srcUserVersion);
    }
    if (!nullToAbsent || bubble != null) {
      map['bubble'] = Variable<String>(bubble);
    }
    if (!nullToAbsent || interCode != null) {
      map['inter_code'] = Variable<String>(interCode);
    }
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<int>(groupId);
    }
    map['is_system_msg'] = Variable<bool>(isSystemMsg);
    map['is_time'] = Variable<bool>(isTime);
    map['direction'] = Variable<String>(direction);
    map['msg_type'] = Variable<String>(msgType);
    map['owner_uin'] = Variable<int>(ownerUin);
    return map;
  }

  ChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ChatMessagesCompanion(
      id: Value(id),
      content: Value(content),
      sessionKey: Value(sessionKey),
      uin: Value(uin),
      time: Value(time),
      extendData: extendData == null && nullToAbsent
          ? const Value.absent()
          : Value(extendData),
      isSuccess: Value(isSuccess),
      notTime: notTime == null && nullToAbsent
          ? const Value.absent()
          : Value(notTime),
      srcUserVersion: srcUserVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(srcUserVersion),
      bubble: bubble == null && nullToAbsent
          ? const Value.absent()
          : Value(bubble),
      interCode: interCode == null && nullToAbsent
          ? const Value.absent()
          : Value(interCode),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      isSystemMsg: Value(isSystemMsg),
      isTime: Value(isTime),
      direction: Value(direction),
      msgType: Value(msgType),
      ownerUin: Value(ownerUin),
    );
  }

  factory ChatMessageRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMessageRecord(
      id: serializer.fromJson<int>(json['id']),
      content: serializer.fromJson<String>(json['content']),
      sessionKey: serializer.fromJson<String>(json['sessionKey']),
      uin: serializer.fromJson<int>(json['uin']),
      time: serializer.fromJson<int>(json['time']),
      extendData: serializer.fromJson<String?>(json['extendData']),
      isSuccess: serializer.fromJson<bool>(json['isSuccess']),
      notTime: serializer.fromJson<int?>(json['notTime']),
      srcUserVersion: serializer.fromJson<String?>(json['srcUserVersion']),
      bubble: serializer.fromJson<String?>(json['bubble']),
      interCode: serializer.fromJson<String?>(json['interCode']),
      groupId: serializer.fromJson<int?>(json['groupId']),
      isSystemMsg: serializer.fromJson<bool>(json['isSystemMsg']),
      isTime: serializer.fromJson<bool>(json['isTime']),
      direction: serializer.fromJson<String>(json['direction']),
      msgType: serializer.fromJson<String>(json['msgType']),
      ownerUin: serializer.fromJson<int>(json['ownerUin']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'content': serializer.toJson<String>(content),
      'sessionKey': serializer.toJson<String>(sessionKey),
      'uin': serializer.toJson<int>(uin),
      'time': serializer.toJson<int>(time),
      'extendData': serializer.toJson<String?>(extendData),
      'isSuccess': serializer.toJson<bool>(isSuccess),
      'notTime': serializer.toJson<int?>(notTime),
      'srcUserVersion': serializer.toJson<String?>(srcUserVersion),
      'bubble': serializer.toJson<String?>(bubble),
      'interCode': serializer.toJson<String?>(interCode),
      'groupId': serializer.toJson<int?>(groupId),
      'isSystemMsg': serializer.toJson<bool>(isSystemMsg),
      'isTime': serializer.toJson<bool>(isTime),
      'direction': serializer.toJson<String>(direction),
      'msgType': serializer.toJson<String>(msgType),
      'ownerUin': serializer.toJson<int>(ownerUin),
    };
  }

  ChatMessageRecord copyWith({
    int? id,
    String? content,
    String? sessionKey,
    int? uin,
    int? time,
    Value<String?> extendData = const Value.absent(),
    bool? isSuccess,
    Value<int?> notTime = const Value.absent(),
    Value<String?> srcUserVersion = const Value.absent(),
    Value<String?> bubble = const Value.absent(),
    Value<String?> interCode = const Value.absent(),
    Value<int?> groupId = const Value.absent(),
    bool? isSystemMsg,
    bool? isTime,
    String? direction,
    String? msgType,
    int? ownerUin,
  }) => ChatMessageRecord(
    id: id ?? this.id,
    content: content ?? this.content,
    sessionKey: sessionKey ?? this.sessionKey,
    uin: uin ?? this.uin,
    time: time ?? this.time,
    extendData: extendData.present ? extendData.value : this.extendData,
    isSuccess: isSuccess ?? this.isSuccess,
    notTime: notTime.present ? notTime.value : this.notTime,
    srcUserVersion: srcUserVersion.present
        ? srcUserVersion.value
        : this.srcUserVersion,
    bubble: bubble.present ? bubble.value : this.bubble,
    interCode: interCode.present ? interCode.value : this.interCode,
    groupId: groupId.present ? groupId.value : this.groupId,
    isSystemMsg: isSystemMsg ?? this.isSystemMsg,
    isTime: isTime ?? this.isTime,
    direction: direction ?? this.direction,
    msgType: msgType ?? this.msgType,
    ownerUin: ownerUin ?? this.ownerUin,
  );
  ChatMessageRecord copyWithCompanion(ChatMessagesCompanion data) {
    return ChatMessageRecord(
      id: data.id.present ? data.id.value : this.id,
      content: data.content.present ? data.content.value : this.content,
      sessionKey: data.sessionKey.present
          ? data.sessionKey.value
          : this.sessionKey,
      uin: data.uin.present ? data.uin.value : this.uin,
      time: data.time.present ? data.time.value : this.time,
      extendData: data.extendData.present
          ? data.extendData.value
          : this.extendData,
      isSuccess: data.isSuccess.present ? data.isSuccess.value : this.isSuccess,
      notTime: data.notTime.present ? data.notTime.value : this.notTime,
      srcUserVersion: data.srcUserVersion.present
          ? data.srcUserVersion.value
          : this.srcUserVersion,
      bubble: data.bubble.present ? data.bubble.value : this.bubble,
      interCode: data.interCode.present ? data.interCode.value : this.interCode,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      isSystemMsg: data.isSystemMsg.present
          ? data.isSystemMsg.value
          : this.isSystemMsg,
      isTime: data.isTime.present ? data.isTime.value : this.isTime,
      direction: data.direction.present ? data.direction.value : this.direction,
      msgType: data.msgType.present ? data.msgType.value : this.msgType,
      ownerUin: data.ownerUin.present ? data.ownerUin.value : this.ownerUin,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessageRecord(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('sessionKey: $sessionKey, ')
          ..write('uin: $uin, ')
          ..write('time: $time, ')
          ..write('extendData: $extendData, ')
          ..write('isSuccess: $isSuccess, ')
          ..write('notTime: $notTime, ')
          ..write('srcUserVersion: $srcUserVersion, ')
          ..write('bubble: $bubble, ')
          ..write('interCode: $interCode, ')
          ..write('groupId: $groupId, ')
          ..write('isSystemMsg: $isSystemMsg, ')
          ..write('isTime: $isTime, ')
          ..write('direction: $direction, ')
          ..write('msgType: $msgType, ')
          ..write('ownerUin: $ownerUin')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    content,
    sessionKey,
    uin,
    time,
    extendData,
    isSuccess,
    notTime,
    srcUserVersion,
    bubble,
    interCode,
    groupId,
    isSystemMsg,
    isTime,
    direction,
    msgType,
    ownerUin,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessageRecord &&
          other.id == this.id &&
          other.content == this.content &&
          other.sessionKey == this.sessionKey &&
          other.uin == this.uin &&
          other.time == this.time &&
          other.extendData == this.extendData &&
          other.isSuccess == this.isSuccess &&
          other.notTime == this.notTime &&
          other.srcUserVersion == this.srcUserVersion &&
          other.bubble == this.bubble &&
          other.interCode == this.interCode &&
          other.groupId == this.groupId &&
          other.isSystemMsg == this.isSystemMsg &&
          other.isTime == this.isTime &&
          other.direction == this.direction &&
          other.msgType == this.msgType &&
          other.ownerUin == this.ownerUin);
}

class ChatMessagesCompanion extends UpdateCompanion<ChatMessageRecord> {
  final Value<int> id;
  final Value<String> content;
  final Value<String> sessionKey;
  final Value<int> uin;
  final Value<int> time;
  final Value<String?> extendData;
  final Value<bool> isSuccess;
  final Value<int?> notTime;
  final Value<String?> srcUserVersion;
  final Value<String?> bubble;
  final Value<String?> interCode;
  final Value<int?> groupId;
  final Value<bool> isSystemMsg;
  final Value<bool> isTime;
  final Value<String> direction;
  final Value<String> msgType;
  final Value<int> ownerUin;
  const ChatMessagesCompanion({
    this.id = const Value.absent(),
    this.content = const Value.absent(),
    this.sessionKey = const Value.absent(),
    this.uin = const Value.absent(),
    this.time = const Value.absent(),
    this.extendData = const Value.absent(),
    this.isSuccess = const Value.absent(),
    this.notTime = const Value.absent(),
    this.srcUserVersion = const Value.absent(),
    this.bubble = const Value.absent(),
    this.interCode = const Value.absent(),
    this.groupId = const Value.absent(),
    this.isSystemMsg = const Value.absent(),
    this.isTime = const Value.absent(),
    this.direction = const Value.absent(),
    this.msgType = const Value.absent(),
    this.ownerUin = const Value.absent(),
  });
  ChatMessagesCompanion.insert({
    this.id = const Value.absent(),
    required String content,
    required String sessionKey,
    required int uin,
    required int time,
    this.extendData = const Value.absent(),
    required bool isSuccess,
    this.notTime = const Value.absent(),
    this.srcUserVersion = const Value.absent(),
    this.bubble = const Value.absent(),
    this.interCode = const Value.absent(),
    this.groupId = const Value.absent(),
    required bool isSystemMsg,
    required bool isTime,
    required String direction,
    this.msgType = const Value.absent(),
    this.ownerUin = const Value.absent(),
  }) : content = Value(content),
       sessionKey = Value(sessionKey),
       uin = Value(uin),
       time = Value(time),
       isSuccess = Value(isSuccess),
       isSystemMsg = Value(isSystemMsg),
       isTime = Value(isTime),
       direction = Value(direction);
  static Insertable<ChatMessageRecord> custom({
    Expression<int>? id,
    Expression<String>? content,
    Expression<String>? sessionKey,
    Expression<int>? uin,
    Expression<int>? time,
    Expression<String>? extendData,
    Expression<bool>? isSuccess,
    Expression<int>? notTime,
    Expression<String>? srcUserVersion,
    Expression<String>? bubble,
    Expression<String>? interCode,
    Expression<int>? groupId,
    Expression<bool>? isSystemMsg,
    Expression<bool>? isTime,
    Expression<String>? direction,
    Expression<String>? msgType,
    Expression<int>? ownerUin,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (content != null) 'content': content,
      if (sessionKey != null) 'session_key': sessionKey,
      if (uin != null) 'uin': uin,
      if (time != null) 'time': time,
      if (extendData != null) 'extend_data': extendData,
      if (isSuccess != null) 'is_success': isSuccess,
      if (notTime != null) 'not_time': notTime,
      if (srcUserVersion != null) 'src_user_version': srcUserVersion,
      if (bubble != null) 'bubble': bubble,
      if (interCode != null) 'inter_code': interCode,
      if (groupId != null) 'group_id': groupId,
      if (isSystemMsg != null) 'is_system_msg': isSystemMsg,
      if (isTime != null) 'is_time': isTime,
      if (direction != null) 'direction': direction,
      if (msgType != null) 'msg_type': msgType,
      if (ownerUin != null) 'owner_uin': ownerUin,
    });
  }

  ChatMessagesCompanion copyWith({
    Value<int>? id,
    Value<String>? content,
    Value<String>? sessionKey,
    Value<int>? uin,
    Value<int>? time,
    Value<String?>? extendData,
    Value<bool>? isSuccess,
    Value<int?>? notTime,
    Value<String?>? srcUserVersion,
    Value<String?>? bubble,
    Value<String?>? interCode,
    Value<int?>? groupId,
    Value<bool>? isSystemMsg,
    Value<bool>? isTime,
    Value<String>? direction,
    Value<String>? msgType,
    Value<int>? ownerUin,
  }) {
    return ChatMessagesCompanion(
      id: id ?? this.id,
      content: content ?? this.content,
      sessionKey: sessionKey ?? this.sessionKey,
      uin: uin ?? this.uin,
      time: time ?? this.time,
      extendData: extendData ?? this.extendData,
      isSuccess: isSuccess ?? this.isSuccess,
      notTime: notTime ?? this.notTime,
      srcUserVersion: srcUserVersion ?? this.srcUserVersion,
      bubble: bubble ?? this.bubble,
      interCode: interCode ?? this.interCode,
      groupId: groupId ?? this.groupId,
      isSystemMsg: isSystemMsg ?? this.isSystemMsg,
      isTime: isTime ?? this.isTime,
      direction: direction ?? this.direction,
      msgType: msgType ?? this.msgType,
      ownerUin: ownerUin ?? this.ownerUin,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (sessionKey.present) {
      map['session_key'] = Variable<String>(sessionKey.value);
    }
    if (uin.present) {
      map['uin'] = Variable<int>(uin.value);
    }
    if (time.present) {
      map['time'] = Variable<int>(time.value);
    }
    if (extendData.present) {
      map['extend_data'] = Variable<String>(extendData.value);
    }
    if (isSuccess.present) {
      map['is_success'] = Variable<bool>(isSuccess.value);
    }
    if (notTime.present) {
      map['not_time'] = Variable<int>(notTime.value);
    }
    if (srcUserVersion.present) {
      map['src_user_version'] = Variable<String>(srcUserVersion.value);
    }
    if (bubble.present) {
      map['bubble'] = Variable<String>(bubble.value);
    }
    if (interCode.present) {
      map['inter_code'] = Variable<String>(interCode.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<int>(groupId.value);
    }
    if (isSystemMsg.present) {
      map['is_system_msg'] = Variable<bool>(isSystemMsg.value);
    }
    if (isTime.present) {
      map['is_time'] = Variable<bool>(isTime.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (msgType.present) {
      map['msg_type'] = Variable<String>(msgType.value);
    }
    if (ownerUin.present) {
      map['owner_uin'] = Variable<int>(ownerUin.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('sessionKey: $sessionKey, ')
          ..write('uin: $uin, ')
          ..write('time: $time, ')
          ..write('extendData: $extendData, ')
          ..write('isSuccess: $isSuccess, ')
          ..write('notTime: $notTime, ')
          ..write('srcUserVersion: $srcUserVersion, ')
          ..write('bubble: $bubble, ')
          ..write('interCode: $interCode, ')
          ..write('groupId: $groupId, ')
          ..write('isSystemMsg: $isSystemMsg, ')
          ..write('isTime: $isTime, ')
          ..write('direction: $direction, ')
          ..write('msgType: $msgType, ')
          ..write('ownerUin: $ownerUin')
          ..write(')'))
        .toString();
  }
}

class $ChatSessionsTable extends ChatSessions
    with TableInfo<$ChatSessionsTable, ChatSessionRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionKeyMeta = const VerificationMeta(
    'sessionKey',
  );
  @override
  late final GeneratedColumn<String> sessionKey = GeneratedColumn<String>(
    'session_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeIdMeta = const VerificationMeta('typeId');
  @override
  late final GeneratedColumn<int> typeId = GeneratedColumn<int>(
    'type_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<String> avatar = GeneratedColumn<String>(
    'avatar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastTimeMeta = const VerificationMeta(
    'lastTime',
  );
  @override
  late final GeneratedColumn<int> lastTime = GeneratedColumn<int>(
    'last_time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastReadTimeMeta = const VerificationMeta(
    'lastReadTime',
  );
  @override
  late final GeneratedColumn<int> lastReadTime = GeneratedColumn<int>(
    'last_read_time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUinMeta = const VerificationMeta(
    'lastUin',
  );
  @override
  late final GeneratedColumn<int> lastUin = GeneratedColumn<int>(
    'last_uin',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastTextMeta = const VerificationMeta(
    'lastText',
  );
  @override
  late final GeneratedColumn<String> lastText = GeneratedColumn<String>(
    'last_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ownerUinMeta = const VerificationMeta(
    'ownerUin',
  );
  @override
  late final GeneratedColumn<int> ownerUin = GeneratedColumn<int>(
    'owner_uin',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionKey,
    typeId,
    name,
    avatar,
    lastTime,
    lastReadTime,
    unreadCount,
    lastUin,
    lastText,
    ownerUin,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatSessionRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_key')) {
      context.handle(
        _sessionKeyMeta,
        sessionKey.isAcceptableOrUnknown(data['session_key']!, _sessionKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionKeyMeta);
    }
    if (data.containsKey('type_id')) {
      context.handle(
        _typeIdMeta,
        typeId.isAcceptableOrUnknown(data['type_id']!, _typeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_typeIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('avatar')) {
      context.handle(
        _avatarMeta,
        avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta),
      );
    }
    if (data.containsKey('last_time')) {
      context.handle(
        _lastTimeMeta,
        lastTime.isAcceptableOrUnknown(data['last_time']!, _lastTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_lastTimeMeta);
    }
    if (data.containsKey('last_read_time')) {
      context.handle(
        _lastReadTimeMeta,
        lastReadTime.isAcceptableOrUnknown(
          data['last_read_time']!,
          _lastReadTimeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastReadTimeMeta);
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_unreadCountMeta);
    }
    if (data.containsKey('last_uin')) {
      context.handle(
        _lastUinMeta,
        lastUin.isAcceptableOrUnknown(data['last_uin']!, _lastUinMeta),
      );
    }
    if (data.containsKey('last_text')) {
      context.handle(
        _lastTextMeta,
        lastText.isAcceptableOrUnknown(data['last_text']!, _lastTextMeta),
      );
    }
    if (data.containsKey('owner_uin')) {
      context.handle(
        _ownerUinMeta,
        ownerUin.isAcceptableOrUnknown(data['owner_uin']!, _ownerUinMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionKey, ownerUin};
  @override
  ChatSessionRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatSessionRecord(
      sessionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_key'],
      )!,
      typeId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}type_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      avatar: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar'],
      ),
      lastTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_time'],
      )!,
      lastReadTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_read_time'],
      )!,
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      lastUin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_uin'],
      ),
      lastText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_text'],
      ),
      ownerUin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}owner_uin'],
      )!,
    );
  }

  @override
  $ChatSessionsTable createAlias(String alias) {
    return $ChatSessionsTable(attachedDatabase, alias);
  }
}

class ChatSessionRecord extends DataClass
    implements Insertable<ChatSessionRecord> {
  final String sessionKey;
  final int typeId;
  final String name;
  final String? avatar;
  final int lastTime;
  final int lastReadTime;
  final int unreadCount;
  final int? lastUin;
  final String? lastText;

  /// 账号归属（本地多账号数据隔离）：0=旧数据（首登收养）。
  final int ownerUin;
  const ChatSessionRecord({
    required this.sessionKey,
    required this.typeId,
    required this.name,
    this.avatar,
    required this.lastTime,
    required this.lastReadTime,
    required this.unreadCount,
    this.lastUin,
    this.lastText,
    required this.ownerUin,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_key'] = Variable<String>(sessionKey);
    map['type_id'] = Variable<int>(typeId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || avatar != null) {
      map['avatar'] = Variable<String>(avatar);
    }
    map['last_time'] = Variable<int>(lastTime);
    map['last_read_time'] = Variable<int>(lastReadTime);
    map['unread_count'] = Variable<int>(unreadCount);
    if (!nullToAbsent || lastUin != null) {
      map['last_uin'] = Variable<int>(lastUin);
    }
    if (!nullToAbsent || lastText != null) {
      map['last_text'] = Variable<String>(lastText);
    }
    map['owner_uin'] = Variable<int>(ownerUin);
    return map;
  }

  ChatSessionsCompanion toCompanion(bool nullToAbsent) {
    return ChatSessionsCompanion(
      sessionKey: Value(sessionKey),
      typeId: Value(typeId),
      name: Value(name),
      avatar: avatar == null && nullToAbsent
          ? const Value.absent()
          : Value(avatar),
      lastTime: Value(lastTime),
      lastReadTime: Value(lastReadTime),
      unreadCount: Value(unreadCount),
      lastUin: lastUin == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUin),
      lastText: lastText == null && nullToAbsent
          ? const Value.absent()
          : Value(lastText),
      ownerUin: Value(ownerUin),
    );
  }

  factory ChatSessionRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatSessionRecord(
      sessionKey: serializer.fromJson<String>(json['sessionKey']),
      typeId: serializer.fromJson<int>(json['typeId']),
      name: serializer.fromJson<String>(json['name']),
      avatar: serializer.fromJson<String?>(json['avatar']),
      lastTime: serializer.fromJson<int>(json['lastTime']),
      lastReadTime: serializer.fromJson<int>(json['lastReadTime']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      lastUin: serializer.fromJson<int?>(json['lastUin']),
      lastText: serializer.fromJson<String?>(json['lastText']),
      ownerUin: serializer.fromJson<int>(json['ownerUin']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionKey': serializer.toJson<String>(sessionKey),
      'typeId': serializer.toJson<int>(typeId),
      'name': serializer.toJson<String>(name),
      'avatar': serializer.toJson<String?>(avatar),
      'lastTime': serializer.toJson<int>(lastTime),
      'lastReadTime': serializer.toJson<int>(lastReadTime),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'lastUin': serializer.toJson<int?>(lastUin),
      'lastText': serializer.toJson<String?>(lastText),
      'ownerUin': serializer.toJson<int>(ownerUin),
    };
  }

  ChatSessionRecord copyWith({
    String? sessionKey,
    int? typeId,
    String? name,
    Value<String?> avatar = const Value.absent(),
    int? lastTime,
    int? lastReadTime,
    int? unreadCount,
    Value<int?> lastUin = const Value.absent(),
    Value<String?> lastText = const Value.absent(),
    int? ownerUin,
  }) => ChatSessionRecord(
    sessionKey: sessionKey ?? this.sessionKey,
    typeId: typeId ?? this.typeId,
    name: name ?? this.name,
    avatar: avatar.present ? avatar.value : this.avatar,
    lastTime: lastTime ?? this.lastTime,
    lastReadTime: lastReadTime ?? this.lastReadTime,
    unreadCount: unreadCount ?? this.unreadCount,
    lastUin: lastUin.present ? lastUin.value : this.lastUin,
    lastText: lastText.present ? lastText.value : this.lastText,
    ownerUin: ownerUin ?? this.ownerUin,
  );
  ChatSessionRecord copyWithCompanion(ChatSessionsCompanion data) {
    return ChatSessionRecord(
      sessionKey: data.sessionKey.present
          ? data.sessionKey.value
          : this.sessionKey,
      typeId: data.typeId.present ? data.typeId.value : this.typeId,
      name: data.name.present ? data.name.value : this.name,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      lastTime: data.lastTime.present ? data.lastTime.value : this.lastTime,
      lastReadTime: data.lastReadTime.present
          ? data.lastReadTime.value
          : this.lastReadTime,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      lastUin: data.lastUin.present ? data.lastUin.value : this.lastUin,
      lastText: data.lastText.present ? data.lastText.value : this.lastText,
      ownerUin: data.ownerUin.present ? data.ownerUin.value : this.ownerUin,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatSessionRecord(')
          ..write('sessionKey: $sessionKey, ')
          ..write('typeId: $typeId, ')
          ..write('name: $name, ')
          ..write('avatar: $avatar, ')
          ..write('lastTime: $lastTime, ')
          ..write('lastReadTime: $lastReadTime, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('lastUin: $lastUin, ')
          ..write('lastText: $lastText, ')
          ..write('ownerUin: $ownerUin')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionKey,
    typeId,
    name,
    avatar,
    lastTime,
    lastReadTime,
    unreadCount,
    lastUin,
    lastText,
    ownerUin,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatSessionRecord &&
          other.sessionKey == this.sessionKey &&
          other.typeId == this.typeId &&
          other.name == this.name &&
          other.avatar == this.avatar &&
          other.lastTime == this.lastTime &&
          other.lastReadTime == this.lastReadTime &&
          other.unreadCount == this.unreadCount &&
          other.lastUin == this.lastUin &&
          other.lastText == this.lastText &&
          other.ownerUin == this.ownerUin);
}

class ChatSessionsCompanion extends UpdateCompanion<ChatSessionRecord> {
  final Value<String> sessionKey;
  final Value<int> typeId;
  final Value<String> name;
  final Value<String?> avatar;
  final Value<int> lastTime;
  final Value<int> lastReadTime;
  final Value<int> unreadCount;
  final Value<int?> lastUin;
  final Value<String?> lastText;
  final Value<int> ownerUin;
  final Value<int> rowid;
  const ChatSessionsCompanion({
    this.sessionKey = const Value.absent(),
    this.typeId = const Value.absent(),
    this.name = const Value.absent(),
    this.avatar = const Value.absent(),
    this.lastTime = const Value.absent(),
    this.lastReadTime = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.lastUin = const Value.absent(),
    this.lastText = const Value.absent(),
    this.ownerUin = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatSessionsCompanion.insert({
    required String sessionKey,
    required int typeId,
    required String name,
    this.avatar = const Value.absent(),
    required int lastTime,
    required int lastReadTime,
    required int unreadCount,
    this.lastUin = const Value.absent(),
    this.lastText = const Value.absent(),
    this.ownerUin = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionKey = Value(sessionKey),
       typeId = Value(typeId),
       name = Value(name),
       lastTime = Value(lastTime),
       lastReadTime = Value(lastReadTime),
       unreadCount = Value(unreadCount);
  static Insertable<ChatSessionRecord> custom({
    Expression<String>? sessionKey,
    Expression<int>? typeId,
    Expression<String>? name,
    Expression<String>? avatar,
    Expression<int>? lastTime,
    Expression<int>? lastReadTime,
    Expression<int>? unreadCount,
    Expression<int>? lastUin,
    Expression<String>? lastText,
    Expression<int>? ownerUin,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionKey != null) 'session_key': sessionKey,
      if (typeId != null) 'type_id': typeId,
      if (name != null) 'name': name,
      if (avatar != null) 'avatar': avatar,
      if (lastTime != null) 'last_time': lastTime,
      if (lastReadTime != null) 'last_read_time': lastReadTime,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (lastUin != null) 'last_uin': lastUin,
      if (lastText != null) 'last_text': lastText,
      if (ownerUin != null) 'owner_uin': ownerUin,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatSessionsCompanion copyWith({
    Value<String>? sessionKey,
    Value<int>? typeId,
    Value<String>? name,
    Value<String?>? avatar,
    Value<int>? lastTime,
    Value<int>? lastReadTime,
    Value<int>? unreadCount,
    Value<int?>? lastUin,
    Value<String?>? lastText,
    Value<int>? ownerUin,
    Value<int>? rowid,
  }) {
    return ChatSessionsCompanion(
      sessionKey: sessionKey ?? this.sessionKey,
      typeId: typeId ?? this.typeId,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      lastTime: lastTime ?? this.lastTime,
      lastReadTime: lastReadTime ?? this.lastReadTime,
      unreadCount: unreadCount ?? this.unreadCount,
      lastUin: lastUin ?? this.lastUin,
      lastText: lastText ?? this.lastText,
      ownerUin: ownerUin ?? this.ownerUin,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionKey.present) {
      map['session_key'] = Variable<String>(sessionKey.value);
    }
    if (typeId.present) {
      map['type_id'] = Variable<int>(typeId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<String>(avatar.value);
    }
    if (lastTime.present) {
      map['last_time'] = Variable<int>(lastTime.value);
    }
    if (lastReadTime.present) {
      map['last_read_time'] = Variable<int>(lastReadTime.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (lastUin.present) {
      map['last_uin'] = Variable<int>(lastUin.value);
    }
    if (lastText.present) {
      map['last_text'] = Variable<String>(lastText.value);
    }
    if (ownerUin.present) {
      map['owner_uin'] = Variable<int>(ownerUin.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatSessionsCompanion(')
          ..write('sessionKey: $sessionKey, ')
          ..write('typeId: $typeId, ')
          ..write('name: $name, ')
          ..write('avatar: $avatar, ')
          ..write('lastTime: $lastTime, ')
          ..write('lastReadTime: $lastReadTime, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('lastUin: $lastUin, ')
          ..write('lastText: $lastText, ')
          ..write('ownerUin: $ownerUin, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FriendsTable extends Friends
    with TableInfo<$FriendsTable, FriendRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FriendsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uinMeta = const VerificationMeta('uin');
  @override
  late final GeneratedColumn<int> uin = GeneratedColumn<int>(
    'uin',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nicknameMeta = const VerificationMeta(
    'nickname',
  );
  @override
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
    'nickname',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<String> avatar = GeneratedColumn<String>(
    'avatar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isOnlineMeta = const VerificationMeta(
    'isOnline',
  );
  @override
  late final GeneratedColumn<bool> isOnline = GeneratedColumn<bool>(
    'is_online',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_online" IN (0, 1))',
    ),
  );
  static const VerificationMeta _gameStatusMeta = const VerificationMeta(
    'gameStatus',
  );
  @override
  late final GeneratedColumn<String> gameStatus = GeneratedColumn<String>(
    'game_status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relationMeta = const VerificationMeta(
    'relation',
  );
  @override
  late final GeneratedColumn<int> relation = GeneratedColumn<int>(
    'relation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _markMeta = const VerificationMeta('mark');
  @override
  late final GeneratedColumn<int> mark = GeneratedColumn<int>(
    'mark',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ownerUinMeta = const VerificationMeta(
    'ownerUin',
  );
  @override
  late final GeneratedColumn<int> ownerUin = GeneratedColumn<int>(
    'owner_uin',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    uin,
    nickname,
    avatar,
    isOnline,
    gameStatus,
    updatedAt,
    relation,
    mark,
    ownerUin,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'friends';
  @override
  VerificationContext validateIntegrity(
    Insertable<FriendRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uin')) {
      context.handle(
        _uinMeta,
        uin.isAcceptableOrUnknown(data['uin']!, _uinMeta),
      );
    } else if (isInserting) {
      context.missing(_uinMeta);
    }
    if (data.containsKey('nickname')) {
      context.handle(
        _nicknameMeta,
        nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta),
      );
    } else if (isInserting) {
      context.missing(_nicknameMeta);
    }
    if (data.containsKey('avatar')) {
      context.handle(
        _avatarMeta,
        avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta),
      );
    }
    if (data.containsKey('is_online')) {
      context.handle(
        _isOnlineMeta,
        isOnline.isAcceptableOrUnknown(data['is_online']!, _isOnlineMeta),
      );
    } else if (isInserting) {
      context.missing(_isOnlineMeta);
    }
    if (data.containsKey('game_status')) {
      context.handle(
        _gameStatusMeta,
        gameStatus.isAcceptableOrUnknown(data['game_status']!, _gameStatusMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('relation')) {
      context.handle(
        _relationMeta,
        relation.isAcceptableOrUnknown(data['relation']!, _relationMeta),
      );
    }
    if (data.containsKey('mark')) {
      context.handle(
        _markMeta,
        mark.isAcceptableOrUnknown(data['mark']!, _markMeta),
      );
    }
    if (data.containsKey('owner_uin')) {
      context.handle(
        _ownerUinMeta,
        ownerUin.isAcceptableOrUnknown(data['owner_uin']!, _ownerUinMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {uin, ownerUin};
  @override
  FriendRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FriendRecord(
      uin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}uin'],
      )!,
      nickname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nickname'],
      )!,
      avatar: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar'],
      ),
      isOnline: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_online'],
      )!,
      gameStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}game_status'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      relation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}relation'],
      )!,
      mark: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mark'],
      )!,
      ownerUin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}owner_uin'],
      )!,
    );
  }

  @override
  $FriendsTable createAlias(String alias) {
    return $FriendsTable(attachedDatabase, alias);
  }
}

class FriendRecord extends DataClass implements Insertable<FriendRecord> {
  final int uin;
  final String nickname;
  final String? avatar;
  final bool isOnline;
  final String? gameStatus;
  final int updatedAt;
  final int relation;
  final int mark;

  /// 账号归属（本地多账号数据隔离）：0=旧数据（首登收养）。
  final int ownerUin;
  const FriendRecord({
    required this.uin,
    required this.nickname,
    this.avatar,
    required this.isOnline,
    this.gameStatus,
    required this.updatedAt,
    required this.relation,
    required this.mark,
    required this.ownerUin,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uin'] = Variable<int>(uin);
    map['nickname'] = Variable<String>(nickname);
    if (!nullToAbsent || avatar != null) {
      map['avatar'] = Variable<String>(avatar);
    }
    map['is_online'] = Variable<bool>(isOnline);
    if (!nullToAbsent || gameStatus != null) {
      map['game_status'] = Variable<String>(gameStatus);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    map['relation'] = Variable<int>(relation);
    map['mark'] = Variable<int>(mark);
    map['owner_uin'] = Variable<int>(ownerUin);
    return map;
  }

  FriendsCompanion toCompanion(bool nullToAbsent) {
    return FriendsCompanion(
      uin: Value(uin),
      nickname: Value(nickname),
      avatar: avatar == null && nullToAbsent
          ? const Value.absent()
          : Value(avatar),
      isOnline: Value(isOnline),
      gameStatus: gameStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(gameStatus),
      updatedAt: Value(updatedAt),
      relation: Value(relation),
      mark: Value(mark),
      ownerUin: Value(ownerUin),
    );
  }

  factory FriendRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FriendRecord(
      uin: serializer.fromJson<int>(json['uin']),
      nickname: serializer.fromJson<String>(json['nickname']),
      avatar: serializer.fromJson<String?>(json['avatar']),
      isOnline: serializer.fromJson<bool>(json['isOnline']),
      gameStatus: serializer.fromJson<String?>(json['gameStatus']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      relation: serializer.fromJson<int>(json['relation']),
      mark: serializer.fromJson<int>(json['mark']),
      ownerUin: serializer.fromJson<int>(json['ownerUin']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uin': serializer.toJson<int>(uin),
      'nickname': serializer.toJson<String>(nickname),
      'avatar': serializer.toJson<String?>(avatar),
      'isOnline': serializer.toJson<bool>(isOnline),
      'gameStatus': serializer.toJson<String?>(gameStatus),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'relation': serializer.toJson<int>(relation),
      'mark': serializer.toJson<int>(mark),
      'ownerUin': serializer.toJson<int>(ownerUin),
    };
  }

  FriendRecord copyWith({
    int? uin,
    String? nickname,
    Value<String?> avatar = const Value.absent(),
    bool? isOnline,
    Value<String?> gameStatus = const Value.absent(),
    int? updatedAt,
    int? relation,
    int? mark,
    int? ownerUin,
  }) => FriendRecord(
    uin: uin ?? this.uin,
    nickname: nickname ?? this.nickname,
    avatar: avatar.present ? avatar.value : this.avatar,
    isOnline: isOnline ?? this.isOnline,
    gameStatus: gameStatus.present ? gameStatus.value : this.gameStatus,
    updatedAt: updatedAt ?? this.updatedAt,
    relation: relation ?? this.relation,
    mark: mark ?? this.mark,
    ownerUin: ownerUin ?? this.ownerUin,
  );
  FriendRecord copyWithCompanion(FriendsCompanion data) {
    return FriendRecord(
      uin: data.uin.present ? data.uin.value : this.uin,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      isOnline: data.isOnline.present ? data.isOnline.value : this.isOnline,
      gameStatus: data.gameStatus.present
          ? data.gameStatus.value
          : this.gameStatus,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      relation: data.relation.present ? data.relation.value : this.relation,
      mark: data.mark.present ? data.mark.value : this.mark,
      ownerUin: data.ownerUin.present ? data.ownerUin.value : this.ownerUin,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FriendRecord(')
          ..write('uin: $uin, ')
          ..write('nickname: $nickname, ')
          ..write('avatar: $avatar, ')
          ..write('isOnline: $isOnline, ')
          ..write('gameStatus: $gameStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('relation: $relation, ')
          ..write('mark: $mark, ')
          ..write('ownerUin: $ownerUin')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    uin,
    nickname,
    avatar,
    isOnline,
    gameStatus,
    updatedAt,
    relation,
    mark,
    ownerUin,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FriendRecord &&
          other.uin == this.uin &&
          other.nickname == this.nickname &&
          other.avatar == this.avatar &&
          other.isOnline == this.isOnline &&
          other.gameStatus == this.gameStatus &&
          other.updatedAt == this.updatedAt &&
          other.relation == this.relation &&
          other.mark == this.mark &&
          other.ownerUin == this.ownerUin);
}

class FriendsCompanion extends UpdateCompanion<FriendRecord> {
  final Value<int> uin;
  final Value<String> nickname;
  final Value<String?> avatar;
  final Value<bool> isOnline;
  final Value<String?> gameStatus;
  final Value<int> updatedAt;
  final Value<int> relation;
  final Value<int> mark;
  final Value<int> ownerUin;
  final Value<int> rowid;
  const FriendsCompanion({
    this.uin = const Value.absent(),
    this.nickname = const Value.absent(),
    this.avatar = const Value.absent(),
    this.isOnline = const Value.absent(),
    this.gameStatus = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.relation = const Value.absent(),
    this.mark = const Value.absent(),
    this.ownerUin = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FriendsCompanion.insert({
    required int uin,
    required String nickname,
    this.avatar = const Value.absent(),
    required bool isOnline,
    this.gameStatus = const Value.absent(),
    required int updatedAt,
    this.relation = const Value.absent(),
    this.mark = const Value.absent(),
    this.ownerUin = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : uin = Value(uin),
       nickname = Value(nickname),
       isOnline = Value(isOnline),
       updatedAt = Value(updatedAt);
  static Insertable<FriendRecord> custom({
    Expression<int>? uin,
    Expression<String>? nickname,
    Expression<String>? avatar,
    Expression<bool>? isOnline,
    Expression<String>? gameStatus,
    Expression<int>? updatedAt,
    Expression<int>? relation,
    Expression<int>? mark,
    Expression<int>? ownerUin,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (uin != null) 'uin': uin,
      if (nickname != null) 'nickname': nickname,
      if (avatar != null) 'avatar': avatar,
      if (isOnline != null) 'is_online': isOnline,
      if (gameStatus != null) 'game_status': gameStatus,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (relation != null) 'relation': relation,
      if (mark != null) 'mark': mark,
      if (ownerUin != null) 'owner_uin': ownerUin,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FriendsCompanion copyWith({
    Value<int>? uin,
    Value<String>? nickname,
    Value<String?>? avatar,
    Value<bool>? isOnline,
    Value<String?>? gameStatus,
    Value<int>? updatedAt,
    Value<int>? relation,
    Value<int>? mark,
    Value<int>? ownerUin,
    Value<int>? rowid,
  }) {
    return FriendsCompanion(
      uin: uin ?? this.uin,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      isOnline: isOnline ?? this.isOnline,
      gameStatus: gameStatus ?? this.gameStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      relation: relation ?? this.relation,
      mark: mark ?? this.mark,
      ownerUin: ownerUin ?? this.ownerUin,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uin.present) {
      map['uin'] = Variable<int>(uin.value);
    }
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<String>(avatar.value);
    }
    if (isOnline.present) {
      map['is_online'] = Variable<bool>(isOnline.value);
    }
    if (gameStatus.present) {
      map['game_status'] = Variable<String>(gameStatus.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (relation.present) {
      map['relation'] = Variable<int>(relation.value);
    }
    if (mark.present) {
      map['mark'] = Variable<int>(mark.value);
    }
    if (ownerUin.present) {
      map['owner_uin'] = Variable<int>(ownerUin.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FriendsCompanion(')
          ..write('uin: $uin, ')
          ..write('nickname: $nickname, ')
          ..write('avatar: $avatar, ')
          ..write('isOnline: $isOnline, ')
          ..write('gameStatus: $gameStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('relation: $relation, ')
          ..write('mark: $mark, ')
          ..write('ownerUin: $ownerUin, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTableTable extends SettingsTable
    with TableInfo<$SettingsTableTable, SettingRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRecord(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTableTable createAlias(String alias) {
    return $SettingsTableTable(attachedDatabase, alias);
  }
}

class SettingRecord extends DataClass implements Insertable<SettingRecord> {
  final String key;
  final String value;
  const SettingRecord({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsTableCompanion toCompanion(bool nullToAbsent) {
    return SettingsTableCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRecord(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRecord copyWith({String? key, String? value}) =>
      SettingRecord(key: key ?? this.key, value: value ?? this.value);
  SettingRecord copyWithCompanion(SettingsTableCompanion data) {
    return SettingRecord(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRecord(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRecord &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsTableCompanion extends UpdateCompanion<SettingRecord> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsTableCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsTableCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRecord> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsTableCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsTableCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsTableCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ChatMessagesTable chatMessages = $ChatMessagesTable(this);
  late final $ChatSessionsTable chatSessions = $ChatSessionsTable(this);
  late final $FriendsTable friends = $FriendsTable(this);
  late final $SettingsTableTable settingsTable = $SettingsTableTable(this);
  late final Index idxChatMessagesOwnerSessionTime = Index(
    'idx_chat_messages_owner_session_time',
    'CREATE INDEX idx_chat_messages_owner_session_time ON chat_messages (owner_uin, session_key, time)',
  );
  late final Index idxChatMessagesOwnerTime = Index(
    'idx_chat_messages_owner_time',
    'CREATE INDEX idx_chat_messages_owner_time ON chat_messages (owner_uin, time)',
  );
  late final Index idxChatSessionsOwnerUin = Index(
    'idx_chat_sessions_owner_uin',
    'CREATE INDEX idx_chat_sessions_owner_uin ON chat_sessions (owner_uin)',
  );
  late final Index idxFriendsOwnerUin = Index(
    'idx_friends_owner_uin',
    'CREATE INDEX idx_friends_owner_uin ON friends (owner_uin)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    chatMessages,
    chatSessions,
    friends,
    settingsTable,
    idxChatMessagesOwnerSessionTime,
    idxChatMessagesOwnerTime,
    idxChatSessionsOwnerUin,
    idxFriendsOwnerUin,
  ];
}

typedef $$ChatMessagesTableCreateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<int> id,
      required String content,
      required String sessionKey,
      required int uin,
      required int time,
      Value<String?> extendData,
      required bool isSuccess,
      Value<int?> notTime,
      Value<String?> srcUserVersion,
      Value<String?> bubble,
      Value<String?> interCode,
      Value<int?> groupId,
      required bool isSystemMsg,
      required bool isTime,
      required String direction,
      Value<String> msgType,
      Value<int> ownerUin,
    });
typedef $$ChatMessagesTableUpdateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<int> id,
      Value<String> content,
      Value<String> sessionKey,
      Value<int> uin,
      Value<int> time,
      Value<String?> extendData,
      Value<bool> isSuccess,
      Value<int?> notTime,
      Value<String?> srcUserVersion,
      Value<String?> bubble,
      Value<String?> interCode,
      Value<int?> groupId,
      Value<bool> isSystemMsg,
      Value<bool> isTime,
      Value<String> direction,
      Value<String> msgType,
      Value<int> ownerUin,
    });

class $$ChatMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionKey => $composableBuilder(
    column: $table.sessionKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get uin => $composableBuilder(
    column: $table.uin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extendData => $composableBuilder(
    column: $table.extendData,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSuccess => $composableBuilder(
    column: $table.isSuccess,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notTime => $composableBuilder(
    column: $table.notTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get srcUserVersion => $composableBuilder(
    column: $table.srcUserVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bubble => $composableBuilder(
    column: $table.bubble,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get interCode => $composableBuilder(
    column: $table.interCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSystemMsg => $composableBuilder(
    column: $table.isSystemMsg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isTime => $composableBuilder(
    column: $table.isTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get msgType => $composableBuilder(
    column: $table.msgType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ownerUin => $composableBuilder(
    column: $table.ownerUin,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionKey => $composableBuilder(
    column: $table.sessionKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uin => $composableBuilder(
    column: $table.uin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extendData => $composableBuilder(
    column: $table.extendData,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSuccess => $composableBuilder(
    column: $table.isSuccess,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notTime => $composableBuilder(
    column: $table.notTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get srcUserVersion => $composableBuilder(
    column: $table.srcUserVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bubble => $composableBuilder(
    column: $table.bubble,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get interCode => $composableBuilder(
    column: $table.interCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSystemMsg => $composableBuilder(
    column: $table.isSystemMsg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isTime => $composableBuilder(
    column: $table.isTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get msgType => $composableBuilder(
    column: $table.msgType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ownerUin => $composableBuilder(
    column: $table.ownerUin,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get sessionKey => $composableBuilder(
    column: $table.sessionKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get uin =>
      $composableBuilder(column: $table.uin, builder: (column) => column);

  GeneratedColumn<int> get time =>
      $composableBuilder(column: $table.time, builder: (column) => column);

  GeneratedColumn<String> get extendData => $composableBuilder(
    column: $table.extendData,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isSuccess =>
      $composableBuilder(column: $table.isSuccess, builder: (column) => column);

  GeneratedColumn<int> get notTime =>
      $composableBuilder(column: $table.notTime, builder: (column) => column);

  GeneratedColumn<String> get srcUserVersion => $composableBuilder(
    column: $table.srcUserVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bubble =>
      $composableBuilder(column: $table.bubble, builder: (column) => column);

  GeneratedColumn<String> get interCode =>
      $composableBuilder(column: $table.interCode, builder: (column) => column);

  GeneratedColumn<int> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<bool> get isSystemMsg => $composableBuilder(
    column: $table.isSystemMsg,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isTime =>
      $composableBuilder(column: $table.isTime, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get msgType =>
      $composableBuilder(column: $table.msgType, builder: (column) => column);

  GeneratedColumn<int> get ownerUin =>
      $composableBuilder(column: $table.ownerUin, builder: (column) => column);
}

class $$ChatMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatMessagesTable,
          ChatMessageRecord,
          $$ChatMessagesTableFilterComposer,
          $$ChatMessagesTableOrderingComposer,
          $$ChatMessagesTableAnnotationComposer,
          $$ChatMessagesTableCreateCompanionBuilder,
          $$ChatMessagesTableUpdateCompanionBuilder,
          (
            ChatMessageRecord,
            BaseReferences<
              _$AppDatabase,
              $ChatMessagesTable,
              ChatMessageRecord
            >,
          ),
          ChatMessageRecord,
          PrefetchHooks Function()
        > {
  $$ChatMessagesTableTableManager(_$AppDatabase db, $ChatMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> sessionKey = const Value.absent(),
                Value<int> uin = const Value.absent(),
                Value<int> time = const Value.absent(),
                Value<String?> extendData = const Value.absent(),
                Value<bool> isSuccess = const Value.absent(),
                Value<int?> notTime = const Value.absent(),
                Value<String?> srcUserVersion = const Value.absent(),
                Value<String?> bubble = const Value.absent(),
                Value<String?> interCode = const Value.absent(),
                Value<int?> groupId = const Value.absent(),
                Value<bool> isSystemMsg = const Value.absent(),
                Value<bool> isTime = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> msgType = const Value.absent(),
                Value<int> ownerUin = const Value.absent(),
              }) => ChatMessagesCompanion(
                id: id,
                content: content,
                sessionKey: sessionKey,
                uin: uin,
                time: time,
                extendData: extendData,
                isSuccess: isSuccess,
                notTime: notTime,
                srcUserVersion: srcUserVersion,
                bubble: bubble,
                interCode: interCode,
                groupId: groupId,
                isSystemMsg: isSystemMsg,
                isTime: isTime,
                direction: direction,
                msgType: msgType,
                ownerUin: ownerUin,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String content,
                required String sessionKey,
                required int uin,
                required int time,
                Value<String?> extendData = const Value.absent(),
                required bool isSuccess,
                Value<int?> notTime = const Value.absent(),
                Value<String?> srcUserVersion = const Value.absent(),
                Value<String?> bubble = const Value.absent(),
                Value<String?> interCode = const Value.absent(),
                Value<int?> groupId = const Value.absent(),
                required bool isSystemMsg,
                required bool isTime,
                required String direction,
                Value<String> msgType = const Value.absent(),
                Value<int> ownerUin = const Value.absent(),
              }) => ChatMessagesCompanion.insert(
                id: id,
                content: content,
                sessionKey: sessionKey,
                uin: uin,
                time: time,
                extendData: extendData,
                isSuccess: isSuccess,
                notTime: notTime,
                srcUserVersion: srcUserVersion,
                bubble: bubble,
                interCode: interCode,
                groupId: groupId,
                isSystemMsg: isSystemMsg,
                isTime: isTime,
                direction: direction,
                msgType: msgType,
                ownerUin: ownerUin,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatMessagesTable, ChatMessageRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChatMessagesTable,
                    ChatMessageRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatMessagesTable,
      ChatMessageRecord,
      $$ChatMessagesTableFilterComposer,
      $$ChatMessagesTableOrderingComposer,
      $$ChatMessagesTableAnnotationComposer,
      $$ChatMessagesTableCreateCompanionBuilder,
      $$ChatMessagesTableUpdateCompanionBuilder,
      (
        ChatMessageRecord,
        BaseReferences<_$AppDatabase, $ChatMessagesTable, ChatMessageRecord>,
      ),
      ChatMessageRecord,
      PrefetchHooks Function()
    >;
typedef $$ChatSessionsTableCreateCompanionBuilder =
    ChatSessionsCompanion Function({
      required String sessionKey,
      required int typeId,
      required String name,
      Value<String?> avatar,
      required int lastTime,
      required int lastReadTime,
      required int unreadCount,
      Value<int?> lastUin,
      Value<String?> lastText,
      Value<int> ownerUin,
      Value<int> rowid,
    });
typedef $$ChatSessionsTableUpdateCompanionBuilder =
    ChatSessionsCompanion Function({
      Value<String> sessionKey,
      Value<int> typeId,
      Value<String> name,
      Value<String?> avatar,
      Value<int> lastTime,
      Value<int> lastReadTime,
      Value<int> unreadCount,
      Value<int?> lastUin,
      Value<String?> lastText,
      Value<int> ownerUin,
      Value<int> rowid,
    });

class $$ChatSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionKey => $composableBuilder(
    column: $table.sessionKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get typeId => $composableBuilder(
    column: $table.typeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastTime => $composableBuilder(
    column: $table.lastTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReadTime => $composableBuilder(
    column: $table.lastReadTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUin => $composableBuilder(
    column: $table.lastUin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastText => $composableBuilder(
    column: $table.lastText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ownerUin => $composableBuilder(
    column: $table.ownerUin,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionKey => $composableBuilder(
    column: $table.sessionKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get typeId => $composableBuilder(
    column: $table.typeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastTime => $composableBuilder(
    column: $table.lastTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReadTime => $composableBuilder(
    column: $table.lastReadTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUin => $composableBuilder(
    column: $table.lastUin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastText => $composableBuilder(
    column: $table.lastText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ownerUin => $composableBuilder(
    column: $table.ownerUin,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionKey => $composableBuilder(
    column: $table.sessionKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get typeId =>
      $composableBuilder(column: $table.typeId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get avatar =>
      $composableBuilder(column: $table.avatar, builder: (column) => column);

  GeneratedColumn<int> get lastTime =>
      $composableBuilder(column: $table.lastTime, builder: (column) => column);

  GeneratedColumn<int> get lastReadTime => $composableBuilder(
    column: $table.lastReadTime,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastUin =>
      $composableBuilder(column: $table.lastUin, builder: (column) => column);

  GeneratedColumn<String> get lastText =>
      $composableBuilder(column: $table.lastText, builder: (column) => column);

  GeneratedColumn<int> get ownerUin =>
      $composableBuilder(column: $table.ownerUin, builder: (column) => column);
}

class $$ChatSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatSessionsTable,
          ChatSessionRecord,
          $$ChatSessionsTableFilterComposer,
          $$ChatSessionsTableOrderingComposer,
          $$ChatSessionsTableAnnotationComposer,
          $$ChatSessionsTableCreateCompanionBuilder,
          $$ChatSessionsTableUpdateCompanionBuilder,
          (
            ChatSessionRecord,
            BaseReferences<
              _$AppDatabase,
              $ChatSessionsTable,
              ChatSessionRecord
            >,
          ),
          ChatSessionRecord,
          PrefetchHooks Function()
        > {
  $$ChatSessionsTableTableManager(_$AppDatabase db, $ChatSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionKey = const Value.absent(),
                Value<int> typeId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> avatar = const Value.absent(),
                Value<int> lastTime = const Value.absent(),
                Value<int> lastReadTime = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int?> lastUin = const Value.absent(),
                Value<String?> lastText = const Value.absent(),
                Value<int> ownerUin = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatSessionsCompanion(
                sessionKey: sessionKey,
                typeId: typeId,
                name: name,
                avatar: avatar,
                lastTime: lastTime,
                lastReadTime: lastReadTime,
                unreadCount: unreadCount,
                lastUin: lastUin,
                lastText: lastText,
                ownerUin: ownerUin,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionKey,
                required int typeId,
                required String name,
                Value<String?> avatar = const Value.absent(),
                required int lastTime,
                required int lastReadTime,
                required int unreadCount,
                Value<int?> lastUin = const Value.absent(),
                Value<String?> lastText = const Value.absent(),
                Value<int> ownerUin = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatSessionsCompanion.insert(
                sessionKey: sessionKey,
                typeId: typeId,
                name: name,
                avatar: avatar,
                lastTime: lastTime,
                lastReadTime: lastReadTime,
                unreadCount: unreadCount,
                lastUin: lastUin,
                lastText: lastText,
                ownerUin: ownerUin,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatSessionsTable, ChatSessionRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChatSessionsTable,
                    ChatSessionRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatSessionsTable,
      ChatSessionRecord,
      $$ChatSessionsTableFilterComposer,
      $$ChatSessionsTableOrderingComposer,
      $$ChatSessionsTableAnnotationComposer,
      $$ChatSessionsTableCreateCompanionBuilder,
      $$ChatSessionsTableUpdateCompanionBuilder,
      (
        ChatSessionRecord,
        BaseReferences<_$AppDatabase, $ChatSessionsTable, ChatSessionRecord>,
      ),
      ChatSessionRecord,
      PrefetchHooks Function()
    >;
typedef $$FriendsTableCreateCompanionBuilder = FriendsCompanion Function({
  required int uin,
  required String nickname,
  Value<String?> avatar,
  required bool isOnline,
  Value<String?> gameStatus,
  required int updatedAt,
  Value<int> relation,
  Value<int> mark,
  Value<int> ownerUin,
  Value<int> rowid,
});
typedef $$FriendsTableUpdateCompanionBuilder = FriendsCompanion Function({
  Value<int> uin,
  Value<String> nickname,
  Value<String?> avatar,
  Value<bool> isOnline,
  Value<String?> gameStatus,
  Value<int> updatedAt,
  Value<int> relation,
  Value<int> mark,
  Value<int> ownerUin,
  Value<int> rowid,
});

class $$FriendsTableFilterComposer
    extends Composer<_$AppDatabase, $FriendsTable> {
  $$FriendsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get uin => $composableBuilder(
    column: $table.uin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOnline => $composableBuilder(
    column: $table.isOnline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gameStatus => $composableBuilder(
    column: $table.gameStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get relation => $composableBuilder(
    column: $table.relation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mark => $composableBuilder(
    column: $table.mark,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ownerUin => $composableBuilder(
    column: $table.ownerUin,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FriendsTableOrderingComposer
    extends Composer<_$AppDatabase, $FriendsTable> {
  $$FriendsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get uin => $composableBuilder(
    column: $table.uin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOnline => $composableBuilder(
    column: $table.isOnline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gameStatus => $composableBuilder(
    column: $table.gameStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get relation => $composableBuilder(
    column: $table.relation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mark => $composableBuilder(
    column: $table.mark,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ownerUin => $composableBuilder(
    column: $table.ownerUin,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FriendsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FriendsTable> {
  $$FriendsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get uin =>
      $composableBuilder(column: $table.uin, builder: (column) => column);

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);

  GeneratedColumn<String> get avatar =>
      $composableBuilder(column: $table.avatar, builder: (column) => column);

  GeneratedColumn<bool> get isOnline =>
      $composableBuilder(column: $table.isOnline, builder: (column) => column);

  GeneratedColumn<String> get gameStatus => $composableBuilder(
    column: $table.gameStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get relation =>
      $composableBuilder(column: $table.relation, builder: (column) => column);

  GeneratedColumn<int> get mark =>
      $composableBuilder(column: $table.mark, builder: (column) => column);

  GeneratedColumn<int> get ownerUin =>
      $composableBuilder(column: $table.ownerUin, builder: (column) => column);
}

class $$FriendsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FriendsTable,
          FriendRecord,
          $$FriendsTableFilterComposer,
          $$FriendsTableOrderingComposer,
          $$FriendsTableAnnotationComposer,
          $$FriendsTableCreateCompanionBuilder,
          $$FriendsTableUpdateCompanionBuilder,
          (
            FriendRecord,
            BaseReferences<_$AppDatabase, $FriendsTable, FriendRecord>,
          ),
          FriendRecord,
          PrefetchHooks Function()
        > {
  $$FriendsTableTableManager(_$AppDatabase db, $FriendsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FriendsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FriendsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FriendsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> uin = const Value.absent(),
                Value<String> nickname = const Value.absent(),
                Value<String?> avatar = const Value.absent(),
                Value<bool> isOnline = const Value.absent(),
                Value<String?> gameStatus = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> relation = const Value.absent(),
                Value<int> mark = const Value.absent(),
                Value<int> ownerUin = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FriendsCompanion(
                uin: uin,
                nickname: nickname,
                avatar: avatar,
                isOnline: isOnline,
                gameStatus: gameStatus,
                updatedAt: updatedAt,
                relation: relation,
                mark: mark,
                ownerUin: ownerUin,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int uin,
                required String nickname,
                Value<String?> avatar = const Value.absent(),
                required bool isOnline,
                Value<String?> gameStatus = const Value.absent(),
                required int updatedAt,
                Value<int> relation = const Value.absent(),
                Value<int> mark = const Value.absent(),
                Value<int> ownerUin = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FriendsCompanion.insert(
                uin: uin,
                nickname: nickname,
                avatar: avatar,
                isOnline: isOnline,
                gameStatus: gameStatus,
                updatedAt: updatedAt,
                relation: relation,
                mark: mark,
                ownerUin: ownerUin,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FriendsTable, FriendRecord>(table),
                  BaseReferences<_$AppDatabase, $FriendsTable, FriendRecord>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FriendsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FriendsTable,
      FriendRecord,
      $$FriendsTableFilterComposer,
      $$FriendsTableOrderingComposer,
      $$FriendsTableAnnotationComposer,
      $$FriendsTableCreateCompanionBuilder,
      $$FriendsTableUpdateCompanionBuilder,
      (
        FriendRecord,
        BaseReferences<_$AppDatabase, $FriendsTable, FriendRecord>,
      ),
      FriendRecord,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableTableCreateCompanionBuilder =
    SettingsTableCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableTableUpdateCompanionBuilder =
    SettingsTableCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTableTable> {
  $$SettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTableTable> {
  $$SettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTableTable> {
  $$SettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTableTable,
          SettingRecord,
          $$SettingsTableTableFilterComposer,
          $$SettingsTableTableOrderingComposer,
          $$SettingsTableTableAnnotationComposer,
          $$SettingsTableTableCreateCompanionBuilder,
          $$SettingsTableTableUpdateCompanionBuilder,
          (
            SettingRecord,
            BaseReferences<_$AppDatabase, $SettingsTableTable, SettingRecord>,
          ),
          SettingRecord,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableTableManager(_$AppDatabase db, $SettingsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsTableCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsTableCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTableTable, SettingRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SettingsTableTable,
                    SettingRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTableTable,
      SettingRecord,
      $$SettingsTableTableFilterComposer,
      $$SettingsTableTableOrderingComposer,
      $$SettingsTableTableAnnotationComposer,
      $$SettingsTableTableCreateCompanionBuilder,
      $$SettingsTableTableUpdateCompanionBuilder,
      (
        SettingRecord,
        BaseReferences<_$AppDatabase, $SettingsTableTable, SettingRecord>,
      ),
      SettingRecord,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ChatMessagesTableTableManager get chatMessages =>
      $$ChatMessagesTableTableManager(_db, _db.chatMessages);
  $$ChatSessionsTableTableManager get chatSessions =>
      $$ChatSessionsTableTableManager(_db, _db.chatSessions);
  $$FriendsTableTableManager get friends =>
      $$FriendsTableTableManager(_db, _db.friends);
  $$SettingsTableTableTableManager get settingsTable =>
      $$SettingsTableTableTableManager(_db, _db.settingsTable);
}
