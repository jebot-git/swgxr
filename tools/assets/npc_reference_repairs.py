"""Narrow repairs for broken NPC CDF paths backed by original wearable metadata.

This is not a missing-mesh fallback. Only the two recorded CDF defects below are
eligible, and their original appearance-table row, SAT and skeleton must agree.
Absent female Tusken gloves and nonexistent hairstyle variants stay unsupported.
"""
from character_formats import datatable, strings
from swg_formats import parse_iff, cstring

TABLE = 'datatables/appearance/appearance_table.iff'
REPAIRS = {
    'appearance/mesh/hat_s04_hum_f.lmg': {
        'row': 'shared_hat_s04', 'column': 'Female Human', 'appearance': 'appearance/hat_s04_f.sat',
        'owners': ('appearance/hum_f.sat',),
        'cdfs': ('clientdata/npc/client_shared_npc_dressed_tatooine_valarian_swooper_leader.cdf',),
        'reason': 'Broken human-specific hat path; the original Female Human table entry and SAT name the exact supported mesh.'},
    'appearance/mesh/armor_chitin_s01_gloves.lmg': {
        'row': 'shared_armor_chitin_s01_gloves', 'column': 'Male Human',
        'appearance': 'appearance/armor_chitin_s01_gloves_m.sat',
        'owners': ('appearance/hum_m.sat', 'appearance/zab_m.sat'),
        'cdfs': ('clientdata/npc/client_shared_npc_dressed_tatooine_desert_demon.cdf',
                 'clientdata/npc/client_shared_npc_dressed_tatooine_desert_demon_leader.cdf'),
        'reason': 'Missing gender suffix; this male owner CDF explicitly uses the male chitin set, whose original Male Human table entry and SAT provide the matching all_b skeleton mesh.'},
}


def resolve_cdf_mesh(importer, source, owner_appearance, source_cdf):
    if source in importer.t.entries or source not in REPAIRS:
        return source, None
    repair = REPAIRS[source]
    if owner_appearance not in repair['owners'] or source_cdf not in repair['cdfs']:
        return source, None
    cdf_meshes = [cstring(node.data)[0] for wear in parse_iff(importer.read(source_cdf)).walk('WEAR')
                  for node in wear.walk('MESH')]
    if source not in cdf_meshes:
        raise ValueError('Broken wearable reference is not present in its authored CDF')
    if repair['row'] == 'shared_armor_chitin_s01_gloves':
        required = {'appearance/mesh/armor_chitin_s01_'+part+'_m.lmg' for part in ('chest_plate', 'leggings', 'boots')}
        if not required <= set(cdf_meshes):
            raise ValueError('Original CDF does not establish the matching male chitin set')
    rows = [row for row in datatable(importer.read(TABLE)) if row['Object Template Name'] == repair['row']]
    if len(rows) != 1 or rows[0][repair['column']] != repair['appearance']:
        raise ValueError('Original appearance table no longer confirms the bounded NPC mesh repair')
    mapped = parse_iff(importer.read(repair['appearance']))
    paths = strings(mapped.first('MSGN').data)
    owner = parse_iff(importer.read(owner_appearance))
    def bindings(raw):
        rows = []; offset = 0
        while offset < len(raw):
            skeleton, offset = cstring(raw, offset); attachment, offset = cstring(raw, offset)
            rows.append((skeleton, attachment))
        return set(rows)
    # Humanoid owners add a face skeleton after the shared all_b skeleton;
    # the wearable must reference an exact subset of those original bindings.
    if len(paths) != 1 or not bindings(mapped.first('SKTI').data) <= bindings(owner.first('SKTI').data):
        raise ValueError('Original repaired wearable does not share the exact owner skeleton')
    resolved = paths[0]
    importer.read(resolved)
    return resolved, {'original_reference': source, 'resolved_reference': resolved,
                      'source_cdf': source_cdf, 'owner_appearance': owner_appearance,
                      'appearance_table': TABLE, 'table_row': repair['row'], 'table_column': repair['column'],
                      'mapped_appearance': repair['appearance'], 'reason': repair['reason'],
                      'policy': 'Explicit original-metadata path repair; source CDF and original mesh bytes remain unchanged.'}
