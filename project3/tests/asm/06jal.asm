.text
main:
  #-------------------------------------------------------------
  # jal tests (black-box, spec-level behavior only)
  #-------------------------------------------------------------

test_2: # forward jal must actually transfer control (skip the trap below)
  li gp, 2
  li x29, 0
  jal x1, target_2
  li x29, 0xdead          # must be skipped
target_2:
  bne x29, x0, fail        # confirm we arrived without falling through the trap


test_3: # jal must store pc+4 (addr of the next instruction) in rd
  li gp, 3
  li x29, 0
  jal x5, do_jalr_3        # x5 should become addr(linkpoint_3)
linkpoint_3:
  addi x29, x29, 1
  j after_3
do_jalr_3:
  jalr x0, x5, 0            # jump using the captured link value; must land exactly on linkpoint_3
  li x29, 0xdead              # should never execute
after_3:
  li x30, 1
  bne x29, x30, fail


test_4: # backward (negative immediate) jal
  li gp, 4
  li x29, 0
  jal x0, forward_4
back_4:
  addi x29, x29, 1
  jal x0, after_4
forward_4:
  jal x0, back_4             # negative-offset jump
after_4:
  li x30, 1
  bne x29, x30, fail


test_5: # jal x0 must discard the link without corrupting x0
  li gp, 5
  jal x0, target_5
target_5:
  bne x0, x0, fail


pass:
  li a0, 1
  ebreak
fail:
  li a0, 0xdead
  ebreak
