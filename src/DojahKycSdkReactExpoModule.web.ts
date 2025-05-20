import { registerWebModule, NativeModule } from 'expo';

import { DojahKycSdkReactExpoModuleEvents } from './DojahKycSdkReactExpo.types';

class DojahKycSdkReactExpoModule extends NativeModule<DojahKycSdkReactExpoModuleEvents> {
  async launch(value: string): Promise<void> {
    this.emit('onChange', { value });
  }
}

export default registerWebModule(DojahKycSdkReactExpoModule, 'DojahKycSdk');
