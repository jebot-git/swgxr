"""Resolve native Core3 gathering snapshots against user-owned original labels."""
from copy import deepcopy
try:
    from .character_protocol import template_names, decode_customization
    from .datapad_protocol import display, template_label
except ImportError:
    from character_protocol import template_names, decode_customization
    from datapad_protocol import display, template_label


def gathering_snapshot(result, oid):
    variables=result.get('variables',{})
    out=deepcopy(variables.get('gathering',{}))
    if out.get('character_id')!=str(oid):raise ValueError('Core3 gathering response owner mismatch or unavailable protocol.')
    if out.get('error'):raise ValueError(out['error'])
    state=out.get('state',{})
    if state.get('source_kind')!='core3_gathering' or state.get('character_id')!=str(oid):raise ValueError('Incomplete Core3 gathering state.')
    names=template_names();attrs=variables.get('weaponAttributes',{})
    def tool(item):
        if item is None:return None
        item['shared_template']=names.get(item.get('client_crc'),'')
        fallback=template_label(item['shared_template'] or item['template'])[0]
        item['name']=item.get('custom_name') or display(item.get('name_table'),item.get('name_key'),fallback)
        item['customization']=decode_customization(bytes.fromhex(item.get('customization_hex','')))
        values=attrs.get('o'+item['id'])
        if values is None:raise ValueError('Missing source tool attributes.')
        item['attributes']=[{'name':k,'value':v} for k,v in values.items() if not k.startswith('swgxr.')]
        return item
    def resource(row):
        if not isinstance(row,dict):return
        for attribute in row.get('attributes',[]):
            key=attribute.get('name','')
            attribute['label']=display('obj_attr_n',key,key.replace('_',' ').capitalize())
        for key in ('type','family'):
            if row.get(key):row[key+'_label']=display('resource/resource_names',row[key],row[key].replace('_',' ').capitalize())
    for row in state.get('resources',[]):resource(row)
    for dep in state.get('deployments',[]):
        resource(dep.get('resource'))
        for row in dep.get('buffer',[]):resource(row)
    resource(out.get('mutation',{}).get('survey',{}).get('resource'))
    state['tool']=tool(state.get('tool'));state['hip_tool']=tool(state.get('hip_tool'))
    if len(state.get('deployments',[]))>16 or len(state.get('resources',[]))>256:raise ValueError('Gathering response exceeds bounds.')
    for dep in state.get('deployments',[]):
        dep['tool']=tool(dep['tool']);dep['shared_template']=dep['tool']['shared_template']
        dep['name']=dep['tool']['name']
        dep['ground_validation']='client_stage_support_only'
        code=dep.get('sample_status','waiting')
        messages={'waiting':'Waiting for next sample','expired':'Resource is no longer available',
                  'full':'Storage full — recover tool to collect resources',
                  'duplicate_type':'Sampling paused — another tool of this type is deployed'}
        fallback=messages.get(code,code.replace('_',' '))
        message=display('survey',code,fallback) if code not in messages else fallback
        dep['sample_message']=message.replace('%TO',dep.get('resource_name','Resource')).replace('%DI',str(dep.get('last_sample_units',0)))
    out['backend']='core3'
    return out


def corpse_snapshot(result, oid):
    out=deepcopy(result.get('variables',{}).get('gathering',{}))
    if out.get('character_id')!=str(oid):raise ValueError('Core3 corpse response owner mismatch or unavailable protocol.')
    if out.get('error'):raise ValueError(out['error'])
    if out.get('source_kind') not in ('core3_corpses','core3_corpse_inspect','core3_corpse_harvest','core3_corpse_loot'):
        raise ValueError('Unexpected native corpse response.')
    names=template_names()
    def resolve(item):
        item['shared_template']=names.get(item.get('client_crc'),'')
        fallback=template_label(item['shared_template'] or item['template'])[0]
        item['name']=item.get('custom_name') or display(item.get('name_table'),item.get('name_key'),fallback)
        item['customization']=decode_customization(bytes.fromhex(item.get('customization_hex','')))
        return item
    records=out.get('corpses',[])
    if out.get('corpse') is not None:records=records+[out['corpse']]
    if len(records)>64:raise ValueError('Corpse response exceeds bounds.')
    for record in records:
        resolve(record)
        # Core3 height is the original appearance scale, without posture modifier.
        record['scale']=record.get('height',1.0)
        for item in record.get('loot',{}).get('items',[]):resolve(item)
    out['backend']='core3'
    return out
