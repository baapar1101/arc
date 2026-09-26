import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/project_service.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

class TaskCycleSection extends StatefulWidget {
  final int businessId;
  final TaskModel task;
  const TaskCycleSection({super.key, required this.businessId, required this.task});
  @override State<TaskCycleSection> createState()=>_TaskCycleSectionState();
}

class _TaskCycleSectionState extends State<TaskCycleSection> {
  late final ProjectService _projects;
  late final TaskService _tasks;
  List<ProjectCycleModel> _available=const [];
  Set<int> _selected=<int>{};
  bool _loading=false,_busy=false;
  String? _error;

  @override void initState(){super.initState();_projects=ProjectService(ApiClient());_tasks=TaskService(ApiClient());_load();}
  @override void didUpdateWidget(covariant TaskCycleSection oldWidget){super.didUpdateWidget(oldWidget);if(oldWidget.task.id!=widget.task.id||oldWidget.task.projectId!=widget.task.projectId)_load();}

  Future<void> _load() async {
    final projectId=widget.task.projectId;
    if(projectId==null){if(mounted)setState((){_available=const[];_selected=<int>{};});return;}
    setState((){_loading=true;_error=null;});
    try{
      final r=await Future.wait<dynamic>([
        _projects.listCycles(businessId:widget.businessId,projectId:projectId),
        _tasks.listTaskCycles(businessId:widget.businessId,taskId:widget.task.id),
      ]);
      if(!mounted)return;
      setState((){_available=r[0] as List<ProjectCycleModel>;_selected=(r[1] as List<TaskCycleModel>).map((e)=>e.id).toSet();_loading=false;});
    }catch(e){if(mounted)setState((){_loading=false;_error=ErrorExtractor.forContext(e,context);});}
  }

  Future<void> _toggle(int id,bool selected) async {
    if(_busy)return;
    final next=Set<int>.from(_selected); selected?next.add(id):next.remove(id);
    setState((){_busy=true;_selected=next;_error=null;});
    try{
      final saved=await _tasks.replaceTaskCycles(businessId:widget.businessId,taskId:widget.task.id,cycleIds:next.toList());
      if(mounted)setState(()=>_selected=saved.map((e)=>e.id).toSet());
    }catch(e){if(mounted)setState(()=>_error=ErrorExtractor.forContext(e,context));await _load();}
    finally{if(mounted)setState(()=>_busy=false);}
  }

  @override Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    if(widget.task.projectId==null)return Text('برای عضویت در Cycle ابتدا پروژه را انتخاب کنید.',style:Theme.of(context).textTheme.bodySmall);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('Cycles / Sprints',style:TextStyle(fontWeight:FontWeight.w700)),
      const SizedBox(height:8),
      if(_loading) const Center(child:CircularProgressIndicator(strokeWidth:2))
      else if(_available.isEmpty) Text('Cycle برای این پروژه تعریف نشده است.',style:Theme.of(context).textTheme.bodySmall)
      else Wrap(spacing:7,runSpacing:7,children:_available.map((cycle)=>FilterChip(
        selected:_selected.contains(cycle.id),
        avatar:const Icon(Icons.autorenew_rounded,size:17),
        label:Text(cycle.name),
        onSelected:_busy?null:(value)=>_toggle(cycle.id,value),
      )).toList()),
      if(_error!=null)...[const SizedBox(height:8),GlassSurface(padding:const EdgeInsets.all(9),borderRadius:BorderRadius.circular(9),child:Text(_error!,style:TextStyle(color:scheme.error)))],
    ]);
  }
}
