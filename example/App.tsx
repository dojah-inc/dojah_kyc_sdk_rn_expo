import { useEvent } from 'expo';
import DojahKycSdk from 'dojah-kyc-sdk-react-expo';
import { Button, SafeAreaView, ScrollView, Text, View } from 'react-native';

export default function App() {
  const onChangePayload = useEvent(DojahKycSdk, 'onChange');

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.container}>
        <Text style={styles.header}>Module API Example</Text>
        <Group name="Dojah KYC">
          <Button
            title="Launch Dojah KYC"
            onPress={async () => {
              console.log('launching Dojah KYC');
              const status = await DojahKycSdk.launch(
                '67a31733f84e4cd6ffbcf06a', null, null, {
                  govId: { 
                     passport: "https://nairametrics.com/wp-content/uploads/2013/11/nigeria-national-identity-smart-cards-combine-id-and-mastercard.jpg"
                  },
                // userData: {
                //   firstName: 'John',
                //   lastName: 'Doe',
                //   email: 'john.doe@example.com',
                //   dob: '1990-01-01'
                // },
                metadata: {
                  "user_id": "1234567890",
                }
              });
              console.log('Dojah KYC status:', status);
            }}
          />
        </Group>
        <Group name="Events">
          <Text>{onChangePayload?.value}</Text>
        </Group>
      </ScrollView>
    </SafeAreaView>
  );
}

function Group(props: { name: string; children: React.ReactNode }) {
  return (
    <View style={styles.group}>
      <Text style={styles.groupHeader}>{props.name}</Text>
      {props.children}
    </View>
  );
}

const styles = {
  header: {
    fontSize: 30,
    margin: 20,
  },
  groupHeader: {
    fontSize: 20,
    marginBottom: 20,
  },
  group: {
    margin: 20,
    backgroundColor: '#fff',
    borderRadius: 10,
    padding: 20,
  },
  container: {
    flex: 1,
    backgroundColor: '#eee',
  },
  view: {
    flex: 1,
    height: 200,
  },
};
