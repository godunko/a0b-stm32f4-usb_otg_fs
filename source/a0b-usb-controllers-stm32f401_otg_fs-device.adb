--
--  Copyright (C) 2025, Vadim Godunko <vgodunko@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

package body A0B.USB.Controllers.STM32F401_OTG_FS.Device is

   procedure OTG_FS_Handler
     with Export, Convention => C, External_Name => "OTG_FS_Handler";

   procedure EXTI18_OTG_FS_Wakeup_Handler
     with Export,
          Convention => C,
          External_Name => "EXTI18_OTG_FS_Wakeup_Handler";

   ----------------------------------
   -- EXTI18_OTG_FS_Wakeup_Handler --
   ----------------------------------

   procedure EXTI18_OTG_FS_Wakeup_Handler is
   begin
      raise Program_Error;
   end EXTI18_OTG_FS_Wakeup_Handler;

   --------------------
   -- OTG_FS_Handler --
   --------------------

   procedure OTG_FS_Handler is
   begin
      OTG_FS.On_Interrupt;
   end OTG_FS_Handler;

end A0B.USB.Controllers.STM32F401_OTG_FS.Device;
