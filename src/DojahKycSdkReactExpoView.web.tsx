import * as React from 'react';

import { DojahKycSdkReactExpoViewProps } from './DojahKycSdkReactExpo.types';

export default function DojahKycSdkReactExpoView(props: DojahKycSdkReactExpoViewProps) {
  return (
    <div>
      <iframe
        style={{ flex: 1 }}
        src={props.url}
        onLoad={() => props.onLoad({ nativeEvent: { url: props.url } })}
      />
    </div>
  );
}
