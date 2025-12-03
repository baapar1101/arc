import 'package:flutter/material.dart';

/// نوع node در workflow
enum WorkflowNodeType {
  trigger,
  action,
  condition,
  loop,
}

/// نوع connection point (ورودی یا خروجی)
enum ConnectionPointType {
  input,
  output,
}

/// مدل یک node در workflow
class WorkflowNodeModel {
  final String id;
  final WorkflowNodeType type;
  final String label;
  final Offset position;
  final Map<String, dynamic> config;
  final String? icon;
  final String? key; // شناسه trigger/action (مثل "invoice.created")
  final String? comment; // یادداشت/توضیح برای node

  WorkflowNodeModel({
    required this.id,
    required this.type,
    required this.label,
    required this.position,
    Map<String, dynamic>? config,
    this.icon,
    this.key,
    this.comment,
  }) : config = config ?? <String, dynamic>{};

  WorkflowNodeModel copyWith({
    String? id,
    WorkflowNodeType? type,
    String? label,
    Offset? position,
    Map<String, dynamic>? config,
    String? icon,
    String? key,
    String? comment,
  }) {
    return WorkflowNodeModel(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      position: position ?? this.position,
      config: config ?? this.config,
      icon: icon ?? this.icon,
      key: key ?? this.key,
      comment: comment ?? this.comment,
    );
  }

  /// تبدیل به فرمت backend
  Map<String, dynamic> toJson() {
    final configMap = <String, dynamic>{};
    
    try {
      configMap.addAll(config);
    } catch (e) {
      debugPrint('خطا در toJson addAll: $e');
      rethrow;
    }
    
    if (type == WorkflowNodeType.trigger && key != null) {
      configMap['trigger_type'] = key;
    }
    if (type == WorkflowNodeType.action && key != null) {
      configMap['action_type'] = key;
    }
    
    final result = <String, dynamic>{
      'id': id,
      'type': type.name,
      'label': label,
      'config': configMap,
    };
    
    if (comment != null && comment!.isNotEmpty) {
      result['comment'] = comment;
    }
    
    return result;
  }

  factory WorkflowNodeModel.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type']?.toString() ?? 'action';
    final type = WorkflowNodeType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => WorkflowNodeType.action,
    );
    
    final configRaw = json['config'];
    final config = <String, dynamic>{};
    if (configRaw is Map) {
      for (final entry in configRaw.entries) {
        config[entry.key.toString()] = entry.value;
      }
    }
    
    String? key;
    if (type == WorkflowNodeType.trigger) {
      key = config['trigger_type']?.toString();
    } else if (type == WorkflowNodeType.action) {
      key = config['action_type']?.toString();
    }

    return WorkflowNodeModel(
      id: json['id']?.toString() ?? '',
      type: type,
      label: json['label']?.toString() ?? '',
      position: Offset.zero, // موقعیت در backend ذخیره نمی‌شود
      config: config,
      key: key,
      comment: json['comment']?.toString(),
    );
  }
}

/// مدل یک اتصال بین دو node
class WorkflowConnectionModel {
  final String id;
  final String sourceNodeId;
  final String targetNodeId;
  final String? sourceOutputId;
  final String? targetInputId;

  WorkflowConnectionModel({
    required this.id,
    required this.sourceNodeId,
    required this.targetNodeId,
    this.sourceOutputId,
    this.targetInputId,
  });

  WorkflowConnectionModel copyWith({
    String? id,
    String? sourceNodeId,
    String? targetNodeId,
    String? sourceOutputId,
    String? targetInputId,
  }) {
    return WorkflowConnectionModel(
      id: id ?? this.id,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      sourceOutputId: sourceOutputId ?? this.sourceOutputId,
      targetInputId: targetInputId ?? this.targetInputId,
    );
  }

  /// تبدیل به فرمت backend
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'source': sourceNodeId,
      'target': targetNodeId,
    };
  }

  factory WorkflowConnectionModel.fromJson(Map<String, dynamic> json) {
    return WorkflowConnectionModel(
      id: '${json['source']}_${json['target']}',
      sourceNodeId: json['source']?.toString() ?? '',
      targetNodeId: json['target']?.toString() ?? '',
    );
  }
}

/// نقاط اتصال (connection points) در node
class ConnectionPoint {
  final String id;
  final String label;
  final ConnectionPointType type;
  final Offset position; // موقعیت نسبی به node
  final String? dataType;

  ConnectionPoint({
    required this.id,
    required this.label,
    required this.type,
    required this.position,
    this.dataType,
  });
}

/// اطلاعات metadata برای trigger یا action
class WorkflowNodeMetadata {
  final String key;
  final String name;
  final String? description;
  final WorkflowNodeType type;
  final Map<String, dynamic>? configSchema;
  final String? icon;

  const WorkflowNodeMetadata({
    required this.key,
    required this.name,
    this.description,
    required this.type,
    this.configSchema,
    this.icon,
  });

  factory WorkflowNodeMetadata.fromJson(
    Map<String, dynamic> json,
    WorkflowNodeType type,
  ) {
    final configSchemaRaw = json['config_schema'];
    Map<String, dynamic>? configSchema;
    if (configSchemaRaw is Map) {
      configSchema = <String, dynamic>{};
      for (final entry in configSchemaRaw.entries) {
        configSchema[entry.key.toString()] = entry.value;
      }
    }
    
    return WorkflowNodeMetadata(
      key: json['key']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      type: type,
      configSchema: configSchema,
    );
  }
}


