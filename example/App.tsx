import { useEvent } from "expo";
import DojahKycSdk from "dojah-kyc-sdk-react-expo";
import { useState } from "react";
import {
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";

export default function App() {
  const onChangePayload = useEvent(DojahKycSdk, "onChange");
  const [widgetId, setWidgetId] = useState("68839af7cc3a4ec28bf1de40");
  const [referenceId, setReferenceId] = useState("");
  const [email, setEmail] = useState("");

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.containerInner}>
        {/* <Text style={styles.header}>DOJAH KYC TEST </Text> */}
        <Group name="Dojah KYC App">
          <Text style={styles.label}>Widget ID:</Text>
          <TextInput
            style={styles.input}
            value={widgetId}
            onChangeText={setWidgetId}
            placeholder="Enter Widget ID"
            placeholderTextColor="#999"
            autoCapitalize="none"
            autoCorrect={false}
          />
          <Text style={styles.label}>Reference ID (Optional):</Text>
          <TextInput
            style={styles.input}
            value={referenceId}
            onChangeText={setReferenceId}
            placeholder="Enter Reference ID"
            placeholderTextColor="#999"
            autoCapitalize="none"
            autoCorrect={false}
          />
          <Text style={styles.label}>Email (Optional):</Text>
          <TextInput
            style={styles.input}
            value={email}
            onChangeText={setEmail}
            placeholder="Enter Email Address"
            placeholderTextColor="#999"
            autoCapitalize="none"
            autoCorrect={false}
            keyboardType="email-address"
          />
          <TouchableOpacity
            style={styles.button}
            onPress={async () => {
              if (!widgetId.trim()) {
                console.log("Please enter a Widget ID");
                return;
              }
              console.log("launching Dojah KYC with widget ID:", widgetId);
              const status = await DojahKycSdk.launch(
                widgetId.trim(),
                referenceId.trim() || null,
                email.trim() || null,
                {
                  govId: {
                    passport:
                      "https://nairametrics.com/wp-content/uploads/2013/11/nigeria-national-identity-smart-cards-combine-id-and-mastercard.jpg",
                  },
                  // userData: {
                  //   firstName: 'John',
                  //   lastName: 'Doe',
                  //   email: 'john.doe@example.com',
                  //   dob: '1990-01-01'
                  // },
                  metadata: {
                    user_id: "1234567890",
                  },
                }
              );
              console.log("Dojah KYC status:", status);
            }}
          >
            <Text style={styles.buttonText}>Launch Dojah KYC</Text>
          </TouchableOpacity>
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

const styles = StyleSheet.create({
  header: {
    fontSize: 30,
    margin: 20,
  },
  button: {
    backgroundColor: "#007bff",
    padding: 10,
    borderRadius: 5,
    marginTop: 20,
    alignItems: "center",
    justifyContent: "center",
  },
  buttonText: {
    color: "#fff",
    fontSize: 16,
    fontWeight: "bold",
  },
  groupHeader: {
    fontSize: 20,
    marginBottom: 20,
    textAlign: "center",
  },
  group: {
    margin: 20,
    marginTop: 30,
    backgroundColor: "#fff",
    borderRadius: 10,
    padding: 20,
  },
  container: {
    flex: 1,
    backgroundColor: "#eee",
  },
  containerInner: {
    marginTop: 50,
  },
  label: {
    fontSize: 16,
    fontWeight: "600",
    marginBottom: 8,
    color: "#333",
  },
  input: {
    borderWidth: 1,
    borderColor: "#ddd",
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
    backgroundColor: "#fff",
    marginBottom: 16,
    color: "#000",
  },
});
