import { requireNativeView } from 'expo';
import * as React from 'react';

import { DojahKycSdkReactExpoViewProps } from './DojahKycSdkReactExpo.types';

const NativeView: React.ComponentType<DojahKycSdkReactExpoViewProps> =
  requireNativeView('DojahKycSdkReactExpo');

export default function DojahKycSdkReactExpoView(props: DojahKycSdkReactExpoViewProps) {
  return <NativeView {...props} />;
}
