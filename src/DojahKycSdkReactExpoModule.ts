import { NativeModule, requireNativeModule } from 'expo';

import { DojahKycSdkReactExpoModuleEvents } from './DojahKycSdkReactExpo.types';

declare class DojahKycSdk extends NativeModule<DojahKycSdkReactExpoModuleEvents> {
  launch(widgetId: string, referenceId?: string | null,
          email?: string | null,
          extraData?: Record<string, any> | null
        ): Promise<string>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<DojahKycSdk>('DojahKycSdk');
