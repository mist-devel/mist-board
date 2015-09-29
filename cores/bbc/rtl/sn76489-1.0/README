
An SN76489AN Compatible Implementation in VHDL
==============================================
Version: $Date: 2006/06/18 19:28:40 $

Copyright (c) 2005, 2006, Arnim Laeuger (arnim.laeuger@gmx.net)
See the file COPYING.


Integration
-----------

The sn76489 design exhibits all interface signals as the original chip. It
only differs in the audio data output which is provided as an 8 bit signed
vector instead of an analog output pin.

  generic (
    clock_div_16_g : integer := 1
    -- Set to '1' when operating the design in SN76489 mode. The primary clock
    -- input is divided by 16 in this variant. The data sheet mentions the
    -- SN76494 which contains a divide-by-2 clock input stage. Set the generic
    -- to '0' to enable this mode.
  );
  port (
    clock_i    : in  std_logic;
    -- Primary clock input
    -- Drive with the target frequency or any integer multiple of it.

    clock_en_i : in  std_logic;
    -- Clock enable
    -- A '1' on this input qualifies a valid rising edge on clock_i. A '0'
    -- disables the next rising clock edge, effectivley halting the design
    -- until the next enabled rising clock edge.
    -- Can be used to run the core at lower frequencies than applied on
    -- clock_i.

    res_n_i    : in  std_logic;
    -- Asynchronous low active reset input.
    -- Sets all sequential elements to a known state.

    ce_n_i     : in  std_logic;
    -- Chip enable, low active.

    we_n_i     : in  std_logic;
    -- Write enable, low active.

    ready_o    : out std_logic;
    -- Ready indication to microprocessor.

    d_i        : in  std_logic_vector(0 to 7);
    -- Data input
    -- MSB 0 ... 7 LSB

    aout_o     : out signed(0 to 7)
    -- Audio output, signed vector
    -- MSB/SIGN 0 ... 7 LSB
  );


Both 8 bit vector ports are defined (0 to 7) which declares bit 0 to be the
MSB and bit 7 to be the LSB. This has been implemented according to TI's data
sheet, thus all register/data format figures apply 1:1 for this design.
Many systems will flip the system data bus bit wise before it is connected to
this PSG. This is simply achieved with the following VHDL construct:

  signal data_s : std_logic_vector(7 downto 0);

  ...
  d_i => data_s,
  ...

d_i and data_s will be assigned from left to right, resulting in the expected
bit assignment:

  d_i    data_s
   0       7
   1       6
      ...
   6       1
   7       0


As this design is fully synchronous, care has to be taken when the design
replaces an SN76489 in asynchronous mode. No problems are expected when
interfacing the code to other synchronous components.


Design Hierarchy
----------------

  sn76489_top
    |
    +-- sn76489_latch_ctrl
    |
    +-- sn76489_clock_div
    |
    +-- sn76489_tone
    |     |
    |     \-- sn76489_attentuator
    |
    +-- sn76489_tone
    |     |
    |     \-- sn76489_attentuator
    |
    +-- sn76489_tone
    |     |
    |     \-- sn76489_attentuator
    |
    \-- sn76489_noise
          |
          \-- sn76489_attentuator

Resulting compilation sequence:

  sn76489_comp_pack-p.vhd
  sn76489_top.vhd
  sn76489_latch_ctrl.vhd
  sn76489_latch_ctrl-c.vhd
  sn76489_clock_div.vhd
  sn76489_clock_div-c.vhd
  sn76489_attenuator.vhd
  sn76489_attenuator-c.vhd
  sn76489_tone.vhd
  sn76489_tone-c.vhd
  sn76489_noise.vhd
  sn76489_noise-c.vhd
  sn76489_top-c.vhd

Skip the files containing VHDL configurations when analyzing the code for
synthesis.


References
----------

* TI Data sheet SN76489.pdf
  ftp://ftp.whtech.com/datasheets%20&%20manuals/SN76489.pdf

* John Kortink's article on the SN76489:
  http://web.inter.nl.net/users/J.Kortink/home/articles/sn76489/

* Maxim's "SN76489 notes" in
  http://www.smspower.org/maxim/docs/SN76489.txt
