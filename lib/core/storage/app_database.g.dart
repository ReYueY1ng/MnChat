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
          ..write('direction: $direction')
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
          other.direction == this.direction);
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
          ..write('direction: $direction')
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
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
          ..write('lastText: $lastText')
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
          other.lastText == this.lastText);
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
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    chatMessages,
    chatSessions,
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
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
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
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ChatMessagesTableTableManager get chatMessages =>
      $$ChatMessagesTableTableManager(_db, _db.chatMessages);
  $$ChatSessionsTableTableManager get chatSessions =>
      $$ChatSessionsTableTableManager(_db, _db.chatSessions);
}
