## Generated SDC file "hello_led.out.sdc"

## Copyright (C) 1991-2011 Altera Corporation
## Your use of Altera Corporation's design tools, logic functions 
## and other software and tools, and its AMPP partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Altera Program License 
## Subscription Agreement, Altera MegaCore Function License 
## Agreement, or other applicable license agreement, including, 
## without limitation, that your use is for the sole purpose of 
## programming logic devices manufactured by Altera and sold by 
## Altera or its authorized distributors.  Please refer to the 
## applicable agreement for further details.


## VENDOR  "Altera"
## PROGRAM "Quartus II"
## VERSION "Version 11.1 Build 216 11/23/2011 Service Pack 1 SJ Web Edition"

## DATE    "Fri Jul 06 23:05:47 2012"

##
## DEVICE  "EP3C25Q240C8"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

create_clock -name clk_27 -period 37.037 [get_ports {CLOCK_27[0]}]
create_clock -name {SPI_SCK}  -period 41.666 -waveform { 20.8 41.666 } [get_ports {SPI_SCK}]

#**************************************************************
# Create Generated Clock
#**************************************************************

derive_pll_clocks

#**************************************************************
# Set Clock Latency
#**************************************************************


#**************************************************************
# Set Clock Uncertainty
#**************************************************************

derive_clock_uncertainty;

#**************************************************************
# Set Input Delay
#**************************************************************

set_input_delay -clock [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[1]}] -max 6.4 [get_ports DRAM_DQ[*]]
set_input_delay -clock [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[1]}] -min 3.2 [get_ports DRAM_DQ[*]]


#**************************************************************
# Set Output Delay
#**************************************************************

set_output_delay -clock [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[1]}] -max 1.5 [get_ports {DRAM_A* DRAM_BA* DRAM_CAS_N DRAM_CKE DRAM_CS_N DRAM_D* DRAM_RAS_N DRAM_WE_N}]
set_output_delay -clock [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[1]}] -min -0.8 [get_ports {DRAM_A* DRAM_BA* DRAM_CAS_N DRAM_CKE DRAM_CS_N DRAM_D* DRAM_RAS_N DRAM_WE_N}]
set_output_delay -clock [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[3]}] -max 1.5 [get_ports DRAM_CLK]
set_output_delay -clock [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[3]}] -min -0.8 [get_ports DRAM_CLK]

set_output_delay -clock [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[2]}] -max 0 [get_ports {VGA_*}]
set_output_delay -clock [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[2]}] -min -5 [get_ports {VGA_*}]

#**************************************************************
# Set Clock Groups
#**************************************************************

set_clock_groups -asynchronous -group [get_clocks {SPI_SCK}] -group [get_clocks {CLOCKS|*}]
set_clock_groups -asynchronous -group [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[0]}] -group [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[2]}]
set_clock_groups -asynchronous -group [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[1]}] -group [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[2]}]

#**************************************************************
# Set False Path
#**************************************************************

#set_false_path -to [get_ports {VGA_*}]
set_false_path -to [get_ports {UART_TX}]
set_false_path -to [get_ports {AUDIO_L}]
set_false_path -to [get_ports {AUDIO_R}]
set_false_path -to [get_ports {LED}]

#**************************************************************
# Set Multicycle Path
#**************************************************************

set_multicycle_path -from [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[0]}] -to [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[1]}] -setup 4
set_multicycle_path -from [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[0]}] -to [get_clocks {CLOCKS|altpll_component|auto_generated|pll1|clk[1]}] -hold 3

set_multicycle_path -to {VGA_*[*]} -setup 2
set_multicycle_path -to {VGA_*[*]} -hold 1

#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************
