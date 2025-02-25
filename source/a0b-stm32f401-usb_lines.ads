--
--  Copyright (C) 2025, Vadim Godunko <vgodunko@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

pragma Ada_2022;

package A0B.STM32F401.USB_Lines
  with Preelaborate, No_Elaboration_Code_All
is

   OTG_FS_DP   : constant Function_Line_Descriptor;
   OTG_FS_DM   : constant Function_Line_Descriptor;
   OTG_FS_ID   : constant Function_Line_Descriptor;
   OTG_FS_VBUS : constant Function_Line_Descriptor;
   OTG_FS_SOF  : constant Function_Line_Descriptor;

private

   OTG_FS_DP : constant Function_Line_Descriptor :=
     [(A, 12, 10)];
   OTG_FS_DM   : constant Function_Line_Descriptor :=
     [(A, 11, 10)];
   OTG_FS_ID   : constant Function_Line_Descriptor :=
     [(A, 10, 10)];
   OTG_FS_VBUS : constant Function_Line_Descriptor :=
     [(A, 9, 10)];
   OTG_FS_SOF  : constant Function_Line_Descriptor :=
     [(A, 8, 10)];

end A0B.STM32F401.USB_Lines;
