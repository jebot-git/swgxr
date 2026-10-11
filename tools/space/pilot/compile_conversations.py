#!/usr/bin/env python3
"""Translate the generated original pilot conversation subset into native Lua.

Requires javalang==0.13.0 in a development-only environment. No Java is executed.
Unknown syntax fails conversion; all engine calls cross an audited shared bridge.
Converted source and original media stay in ignored runtime directories.
"""
import argparse
import collections
import hashlib
import json
import re
from pathlib import Path
import javalang
from javalang import tree as T

ROOT = Path(__file__).resolve().parents[3]
OPS = {'&&':'and', '||':'or', '!=':'~=', '!':'not '}
METHODS = ('_condition_', '_action_', '_handleBranch')


def quote(value):
    return json.dumps(value, ensure_ascii=True)


class SourceParser(javalang.parser.Parser):
    """Preserve parenthesized unary expressions lost by javalang 0.13.0.

    parse_primary returns the inner AST for parentheses; upstream expression_3
    then overwrites its operators/selectors. Keep those before that overwrite.
    """
    def parse_expression_3(self):
        if not hasattr(self, '_primary_frames'):self._primary_frames=[]
        self._primary_frames.append(None)
        try:
            result=super().parse_expression_3()
            saved=self._primary_frames[-1]
            if saved and saved[0] is result:
                for attribute,previous in saved[1].items():
                    current=getattr(result,attribute,[]) or []
                    setattr(result,attribute,current+previous if attribute=='prefix_operators' else previous+current)
            return result
        finally:self._primary_frames.pop()
    def parse_primary(self):
        result=super().parse_primary()
        self._primary_frames[-1]=(result,{key:list(getattr(result,key,[]) or []) for key in ('prefix_operators','postfix_operators','selectors')})
        return result

def parse_source(raw):return SourceParser(javalang.tokenizer.tokenize(raw)).parse()


class Compiler:
    def __init__(self, name):
        self.name = name
        self.calls = collections.Counter()

    def expr(self, n):
        if n is None: return 'nil'
        if isinstance(n, T.Literal):
            out = n.value
            if out == 'null': out = 'nil'
            elif not out.startswith('"'): out = re.sub(r'[fFdDlL]$', '', out)
        elif isinstance(n, T.MemberReference):
            if n.qualifier:
                if n.qualifier in ('space_flags','space_quest','factions'):
                    out = 'PilotSource.constant('+quote(n.qualifier+'.'+n.member)+')'
                else: out = n.qualifier+'.'+n.member
            elif n.member == 'c_stringFile': out = 'self.stringFile'
            elif n.member == 'self': out = 'npcSelf'
            elif n.member.startswith(('SCRIPT_', 'SPECIES_', 'GENDER_')):
                out = 'PilotSource.constant('+quote(n.member)+')'
            else: out = n.member
        elif isinstance(n, T.BinaryOperation):
            left, right = self.expr(n.operandl), self.expr(n.operandr)
            out = 'PilotSource.add('+left+','+right+')' if n.operator == '+' else '('+left+' '+OPS.get(n.operator,n.operator)+' '+right+')'
        elif isinstance(n, T.MethodInvocation):
            args = ','.join(self.expr(x) for x in n.arguments)
            if n.member.startswith(self.name+'_'):
                out = 'self:'+n.member[len(self.name)+1:]+'('+args+')'
            elif n.member == 'equals':
                out = '('+n.qualifier+' == '+args+')'
            else:
                call = (n.qualifier+'.' if n.qualifier else '')+n.member
                self.calls[call] += 1
                out = 'PilotSource.call(self,'+quote(call)+(','+args if args else '')+')'
        elif isinstance(n, T.ClassCreator):
            kind = n.type.name
            if kind == 'string_id': out = '('+self.expr(n.arguments[0])+'..":"..'+self.expr(n.arguments[1])+')'
            elif kind == 'prose_package': out = '{}'
            elif kind == 'location': out = '{planet='+self.expr(n.arguments[3])+',x='+self.expr(n.arguments[0])+',y='+self.expr(n.arguments[1])+',z='+self.expr(n.arguments[2])+'}'
            else: raise ValueError('Unsupported constructor '+kind)
        elif isinstance(n, T.ArrayCreator):
            out = self.expr(n.initializer) if n.initializer else '{}'
        elif isinstance(n, T.ArrayInitializer):
            out = '{'+','.join('['+str(i)+']='+self.expr(v) for i,v in enumerate(n.initializers))+'}'
        elif isinstance(n, T.Assignment):
            left, right = self.expr(n.expressionl), self.expr(n.value)
            out = left+'='+right if n.type == '=' else left+'='+left+n.type[:-1]+right
        else: raise ValueError('Unsupported expression '+type(n).__name__)
        for selector in getattr(n,'selectors',[]) or []:
            if isinstance(selector, T.ArraySelector): out += '['+self.expr(selector.index)+']'
            else: raise ValueError('Unsupported selector '+repr(selector))
        for operator in reversed(getattr(n,'prefix_operators',[]) or []):
            if operator not in ('++','--'): out = '('+OPS.get(operator,operator)+out+')'
        return out

    def body(self, nodes):
        return '\n'.join(self.statement(n) for n in nodes or [])

    def statement(self, n):
        if isinstance(n, T.BlockStatement): return 'do\n'+self.body(n.statements)+'\nend'
        if isinstance(n, (T.LocalVariableDeclaration,T.VariableDeclaration)):
            return '\n'.join('local '+x.name+'='+self.expr(x.initializer) for x in n.declarators)
        if isinstance(n, T.StatementExpression):
            e=n.expression
            if isinstance(e,T.MemberReference) and ('++' in e.prefix_operators+e.postfix_operators or '--' in e.prefix_operators+e.postfix_operators):
                v=self.expr(e);return v+'='+v+(' + 1' if '++' in e.prefix_operators+e.postfix_operators else ' - 1')
            increments=[]
            for _,child in e:
                if isinstance(child,T.MemberReference) and child.postfix_operators:
                    if child.postfix_operators!=['++']:raise ValueError('Unsupported postfix '+str(child))
                    increments.append(child.member+'='+child.member+'+1')
            return self.expr(e)+(';'+';'.join(increments) if increments else '')
        if isinstance(n,T.IfStatement):
            return 'if '+self.expr(n.condition)+' then\n'+self.statement(n.then_statement)+(('\nelse\n'+self.statement(n.else_statement)) if n.else_statement else '')+'\nend'
        if isinstance(n,T.ReturnStatement): return 'do return '+self.expr(n.expression)+' end'
        if isinstance(n,T.ForStatement) and isinstance(n.control,T.EnhancedForControl):
            return 'for _, '+n.control.var.declarators[0].name+' in PilotSource.values('+self.expr(n.control.iterable)+') do\n'+self.statement(n.body)+'\nend'
        if isinstance(n,T.SwitchStatement):
            lines=['do local switch_value='+self.expr(n.expression)]
            for i,case in enumerate(n.cases):
                lines.append(('if ' if i==0 else 'elseif ')+ ' or '.join('switch_value=='+self.expr(c) for c in case.case)+' then')
                lines.append(self.body([v for v in case.statements if not isinstance(v,T.BreakStatement)]))
            return '\n'.join(lines)+'\nend\nend'
        raise ValueError('Unsupported statement '+type(n).__name__)

    def compile(self, raw):
        ast=parse_source(raw)
        fields=ast.types[0].fields
        string_file=next(d.initializer.value.strip('"') for f in fields for d in f.declarators if d.name=='c_stringFile')
        out=['-- Generated from pinned original SWG source. Engine behavior lives in PilotSource.',self.name+'={stringFile='+quote('@'+string_file)+'}']
        count=0
        methods={m.name:m for m in ast.types[0].methods}
        reachable=set();pending=['OnStartNpcConversation','OnNpcConversationResponse']
        while pending:
            name=pending.pop()
            if name in reachable:continue
            reachable.add(name)
            for _,node in methods[name]:
                if isinstance(node,T.MethodInvocation) and node.member.startswith(self.name+"_") and node.member in methods:
                    pending.append(node.member)
        for method in ast.types[0].methods:
            if method.name not in reachable:continue
            name=method.name.removeprefix(self.name+'_')
            args=[p.name for p in method.parameters]
            # Java self means the NPC; Lua self is this conversation program.
            body=self.body(method.body)
            if 'self' in args:
                args=['npcSelf' if p=='self' else p for p in args]
            out.append('function '+self.name+':'+name+'('+','.join(args)+')\n'+body+'\nend')
            count+=1
        return '\n'.join(out)+'\n',count


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,default=ROOT/'runtime/reference/pilot-progression')
    p.add_argument('--out',type=Path,default=ROOT/'runtime/server/pilot-source')
    a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
    report={'sources':[],'calls':{},'errors':[]}
    programs=set(json.loads((ROOT/'server/jtl/pilot/trainers.json').read_text()).values())
    for path in sorted(a.source/(name+'.java') for name in programs):
        if 'c_stringFile' not in path.read_text():continue
        compiler=Compiler(path.stem)
        try:
            raw=path.read_bytes();code,count=compiler.compile(raw.decode())
            (a.out/(path.stem+'.lua')).write_text(code)
            report['sources'].append({'name':path.stem,'sha256':hashlib.sha256(raw).hexdigest(),'functions':count,'output_sha256':hashlib.sha256(code.encode()).hexdigest()})
            for k,v in compiler.calls.items():report['calls'][k]=report['calls'].get(k,0)+v
        except Exception as error: report['errors'].append({'source':path.name,'error':str(error)})
    (a.out/'conversion.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'converted':len(report['sources']),'errors':report['errors']}))
    return bool(report['errors'])


if __name__=='__main__':raise SystemExit(main())
