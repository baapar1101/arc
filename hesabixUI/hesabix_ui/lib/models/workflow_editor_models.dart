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

  WorkflowNodeModel({
    required this.id,
    required this.type,
    required this.label,
    required this.position,
    this.config = const {},
    this.icon,
    this.key,
  });

  WorkflowNodeModel copyWith({
    String? id,
    WorkflowNodeType? type,
    String? label,
    Offset? position,
    Map<String, dynamic>? config,
    String? icon,
    String? key,
  }) {
    return WorkflowNodeModel(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      position: position ?? this.position,
      config: config ?? this.config,
      icon: icon ?? this.icon,
      key: key ?? this.key,
    );
  }

  /// تبدیل به فرمت backend
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'label': label,
      'config': {
        ...config,
        if (type == WorkflowNodeType.trigger && key != null)
          'trigger_type': key,
        if (type == WorkflowNodeType.action && key != null)
          'action_type': key,
      },
    };
  }

  factory WorkflowNodeModel.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'action';
    final type = WorkflowNodeType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => WorkflowNodeType.action,
    );

    final config = json['config'] as Map<String, dynamic>? ?? {};
    String? key;
    if (type == WorkflowNodeType.trigger) {
      key = config['trigger_type'] as String?;
    } else if (type == WorkflowNodeType.action) {
      key = config['action_type'] as String?;
    }

    return WorkflowNodeModel(
      id: json['id'] as String? ?? '',
      type: type,
      label: json['label'] as String? ?? '',
      position: Offset.zero, // موقعیت در backend ذخیره نمی‌شود
      config: config,
      key: key,
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
    return {
      'source': sourceNodeId,
      'target': targetNodeId,
    };
  }

  factory WorkflowConnectionModel.fromJson(Map<String, dynamic> json) {
    return WorkflowConnectionModel(
      id: '${json['source']}_${json['target']}',
      sourceNodeId: json['source'] as String? ?? '',
      targetNodeId: json['target'] as String? ?? '',
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

  WorkflowNodeMetadata({
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
    return WorkflowNodeMetadata(
      key: json['key'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      type: type,
      configSchema: json['config_schema'] as Map<String, dynamic>?,
    );
  }
}


