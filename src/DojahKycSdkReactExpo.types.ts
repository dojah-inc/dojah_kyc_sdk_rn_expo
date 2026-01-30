import type { StyleProp, ViewStyle } from 'react-native';

export type OnLoadEventPayload = {
  url: string;
};

export type DojahKycSdkReactExpoModuleEvents = {
  onChange: (params: ChangeEventPayload) => void;
  onDebugLog: (params: DebugLogEventPayload) => void;
};

export type ChangeEventPayload = {
  value: string;
};

export type DebugLogEventPayload = {
  message: string;
  timestamp: number;
};

export type DojahKycSdkReactExpoViewProps = {
  url: string;
  onLoad: (event: { nativeEvent: OnLoadEventPayload }) => void;
  style?: StyleProp<ViewStyle>;
};
