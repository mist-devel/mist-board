library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package my_math_pkg is

    function sum_limit(i1, i2 : signed) return signed;
    function sub_limit(i1, i2 : signed) return signed;
    function sum_limit(i1, i2 : unsigned) return unsigned;
    function extend(x : signed; len : natural) return signed;
    function extend(x : unsigned; len : natural) return unsigned;
    function left_align(x : signed; len : natural) return signed;
    function left_scale(x : signed; sh : natural) return signed;
    
--    function shift_right(x : signed; positions: natural) return signed;
end;

package body my_math_pkg is

    function sum_limit(i1, i2 : signed) return signed is
        variable o : signed(i1'range);
    begin
        assert i1'length = i2'length
            report "i1 and i2 should have the same length!"
            severity failure;
        o := i1 + i2;
        if (i1(i1'left) = i2(i2'left)) and (o(o'left) /= i1(i1'left)) then
            if i1(i1'left)='1' then
                o := to_signed(-(2**(o'length-1)), o'length);
            else
                o := to_signed(2**(o'length-1) - 1, o'length);
            end if;
        end if;
        return o;
    end function;

    function sub_limit(i1, i2 : signed) return signed is
        variable o : signed(i1'range);
    begin
        assert i1'length = i2'length
            report "i1 and i2 should have the same length!"
            severity failure;
        o := i1 - i2;
        if (i1(i1'left) /= i2(i2'left)) and (o(o'left) /= i1(i1'left)) then
            if i1(i1'left)='1' then
                o := to_signed(-(2**(o'length-1)), o'length);
            else
                o := to_signed(2**(o'length-1) - 1, o'length);
            end if;
        end if;
        return o;            
    end function;

    function sum_limit(i1, i2 : unsigned) return unsigned is
        variable o : unsigned(i1'length downto 0);
    begin
        o := ('0' & i1) + i2;
        if o(o'left)='1' then
            o := (others => '1');
        end if;
        return o(i1'length-1 downto 0);
    end function;

    function extend(x : signed; len : natural) return signed is
        variable ret : signed(len-1 downto 0);
        alias a      : signed(x'length-1 downto 0) is x;
    begin
        ret := (others => x(x'left));
        ret(a'range) := a;
        return ret;
    end function extend;

    function extend(x : unsigned; len : natural) return unsigned is
        variable ret : unsigned(len-1 downto 0);
        alias a      : unsigned(x'length-1 downto 0) is x;
    begin
        ret := (others => '0');
        ret(a'range) := a;
        return ret;
    end function extend;

    function left_align(x : signed; len : natural) return signed is
        variable ret : signed(len-1 downto 0);
    begin
        ret := (others => '0');
        ret(len-1 downto len-x'length) := x;
        return ret;
    end function left_align;

    function left_scale(x : signed; sh : natural) return signed is
        alias a      : signed(x'length-1 downto 0) is x;
        variable ret : signed(x'length-(1+sh) downto 0);
        variable top : signed(sh downto 0);
    begin
        if sh=0 then
            return x;
        end if;
        
        top := a(a'high downto a'high-sh);
        if (top = -1) or (top = 0) then -- can shift without getting punished!
            ret := a(ret'range);
        elsif a(a'high)='1' then -- negative and can't shift, so max neg:
            ret := (others => '0');
            ret(ret'high) := '1';
        else -- positive and can't shift, so max pos
            ret := (others => '1');
            ret(ret'high) := '0';
        end if;
        return ret;
    end function left_scale;

--    function shift_right(x : signed; positions: natural) return signed is
--        alias a      : signed(x'length-1 downto 0) is x;
--        variable ret : signed(x'length-1 downto 0);
--    begin
--        ret := (others => x(x'left));
--        ret(a'left-positions downto 0) := a(a'left downto positions);
--        return ret;
--    end function shift_right;
end;
