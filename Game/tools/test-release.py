"""Run maintained regressions, with isolated fixtures outside Game."""
from pathlib import Path
import subprocess, json, argparse, os
P=Path(__file__).resolve().parents[2];G=P/'Game/Godot'
ENGINE=P/'_tools/runtime/godot-build/godot/Godot_v4.7.2-stable_win64_console.exe'
LOGS=P/'_work/tests/logs'
LOGIC=['test_parity','test_blink','test_meal','test_satiety','test_bowl_shout','test_bowl_edges','test_drag_eye_transition','test_roaming','test_walking_knees','test_bowl_impact','test_bowl_summon','test_catch_challenge','test_catch_physics','test_game_scores','test_juggle','test_bowl_roll','test_app_update']
RENDER=['test_bowl','test_shared_arm_rig','test_feeding_hold_rig','test_food_scarf_depth','test_braid_depth','test_expression_masks','test_bite_handoff','test_bowl_drop','test_bowl_edge_host','test_bowl_host','test_bowl_e2e','test_menu_idle','test_settings_menu','test_bowl_hit_host','test_desktop_shell','test_bowl_startup','test_bowl_summon_host','test_catch_host','test_catch_score_lifecycle','test_score_board','test_juggle_host','test_juggle_render','test_pet_hit_area','test_physics_host','test_rehit_render','test_drag_release']
RENDER += ['test_dizzy_grab']
LOGIC += ['test_size_change']
RENDER += ['test_size_change_host','test_mushroom_hold','test_bowl_resize']
LOGIC += ['test_ai_transport','test_ai_companion','test_ai_speech','test_ai_keys']
RENDER += ['test_ai_ui','test_ai_host','test_all_speech']
LOGIC += ['test_proactive_scheduler','test_ai_auth_route','test_chatgpt_auth']
LOGIC += ['test_proactive_topics']
RENDER += ['test_proactive_card','test_proactive_host']
LOGIC += ['test_ai_deepseek']
RENDER += ['test_chatgpt_auth_ui','test_deepseek_ui']
LOGIC += ['test_ai_memory_ledger','test_ai_memory_service','test_ai_memory_compaction','test_speech_speed','test_text_reveal']
RENDER += ['test_chat_idle','test_full_chat_idle','test_chat_window_opacity','test_speech_speed_host','test_text_reveal_windows']
RENDER += ['test_oversized_food_host']
LOGIC += ['test_sleep_cycle']
RENDER += ['test_sleep_render','test_sleep_settings','test_sleep_host']

def main():
    p=argparse.ArgumentParser();p.add_argument('--group',choices=['logic','render','native','all'],default='all');p.add_argument('--tests',nargs='*');args=p.parse_args()
    LOGS.mkdir(parents=True,exist_ok=True);results=[]
    jobs=[]
    for name in (LOGIC if args.group in ['all','logic'] else [])+(RENDER if args.group in ['all','render'] else []):
        extra=['--','--root='+str(P/'_work/tests/ai-key-vault')] if name=='test_ai_keys' else []
        jobs.append((name,[str(ENGINE),'--path',str(G),*(['--headless'] if name in LOGIC else []),'--script','res://tests/'+name+'.gd',*extra]))
    if args.group in ['all','native']:
        for name in ['test_bowl_files','test_digestion','test_desktop_shell']:
            jobs.append((name,['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(G/'tests'/f'{name}.ps1')]))
    for name,command in jobs:
        if args.tests and name not in args.tests:continue
        try:
            r=subprocess.run(command,cwd=G,capture_output=True,timeout=240)
            output=(r.stdout+r.stderr).decode('utf-8',errors='replace');code=r.returncode
            if 'ERROR:' in output or 'Parse Error:' in output:code=1
        except subprocess.TimeoutExpired as e:output=str(e)+'\n'+((e.stdout or b'')+(e.stderr or b'')).decode('utf-8',errors='replace');code=124
        (LOGS/(name+'.log')).write_text(output,encoding='utf-8')
        results.append({'test':name,'exitCode':code})
        print(name,'PASS' if code==0 else f'FAIL {code}',flush=True)
    result_path=LOGS/(args.group+'-results.json')
    if args.tests and result_path.exists():
        previous=json.loads(result_path.read_text(encoding='utf-8'))
        results=[x for x in previous if x['test'] not in args.tests]+results
    result_path.write_text(json.dumps(results,indent=2),encoding='utf-8')
    raise SystemExit(1 if any(x['exitCode'] for x in results) else 0)
if __name__=='__main__':main()
