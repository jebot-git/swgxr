#!/usr/bin/env python3
"""Regressions for source conditions which previously blocked higher pilot tiers."""
import unittest
from lupa import LuaRuntime
from compile_conversations import SourceParser,Compiler
import javalang
class ConversionTests(unittest.TestCase):
 def evaluate(self,expression,flag):
  parser=SourceParser(javalang.tokenizer.tokenize(expression+";"));node=parser.parse_expression()
  code=Compiler('fixture').expr(node);lua=LuaRuntime();lua.execute('PilotSource={call=function() return '+('true' if flag else 'false')+' end}')
  return lua.eval(code)
 def test_parenthesized_unary_and_double_negation(self):
  for expression in ('(!hasSkill(player,"x"))','((!hasSkill(player,"x")))','!(hasSkill(player,"x"))'):
   with self.subTest(expression=expression):
    self.assertFalse(self.evaluate(expression,True));self.assertTrue(self.evaluate(expression,False))
  self.assertTrue(self.evaluate('!(!hasSkill(player,"x"))',True))
 def test_nested_gate_keeps_boolean_precedence(self):
  self.assertFalse(self.evaluate('(true && (!hasSkill(player,"x"))) || false',True))
  self.assertTrue(self.evaluate('(true && (!hasSkill(player,"x"))) || false',False))
if __name__=='__main__':unittest.main()
