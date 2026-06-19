# APEX Safety FSM — simulation shortcuts
SRC := rtl/safety_fsm.sv tb/safety_fsm_tb.sv

sim:          ## Compile + run the self-checking testbench
	iverilog -g2012 -o sim.out $(SRC)
	vvp sim.out

wave: sim     ## Run, then open waveforms in GTKWave
	gtkwave safety_fsm.vcd

clean:
	rm -f sim.out *.vcd *.log

.PHONY: sim wave clean
