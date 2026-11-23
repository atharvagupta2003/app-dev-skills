import { Feather } from '@expo/vector-icons';
import {
  SpaceGrotesk_400Regular,
  SpaceGrotesk_500Medium,
  SpaceGrotesk_700Bold,
  useFonts,
} from '@expo-google-fonts/space-grotesk';
import { LinearGradient } from 'expo-linear-gradient';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import { Animated, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';

const ACCENT = '#C6FF3D';
const TAGS = [
  { name: 'Work', color: '#7C9CFF' },
  { name: 'Ideas', color: '#FF8AD8' },
  { name: 'Travel', color: '#5EEAD4' },
];
const RECENT = [
  { title: 'Sprint review notes', tag: 'Work', time: '9:40 am', color: '#7C9CFF' },
  { title: 'Lisbon packing list', tag: 'Travel', time: 'Yesterday', color: '#5EEAD4' },
  { title: 'App name shortlist', tag: 'Ideas', time: 'Mon', color: '#FF8AD8' },
];

export default function App() {
  const [fontsLoaded] = useFonts({ SpaceGrotesk_400Regular, SpaceGrotesk_500Medium, SpaceGrotesk_700Bold });
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [tag, setTag] = useState('Ideas');
  const [saved, setSaved] = useState<string | null>(null);
  const enter = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.timing(enter, { toValue: 1, duration: 500, useNativeDriver: true }).start();
  }, [enter]);

  if (!fontsLoaded) return null;

  const save = () => {
    if (!title.trim()) return;
    setSaved(title.trim());
    setTitle('');
    setBody('');
  };

  return (
    <View style={styles.screen}>
      <StatusBar style="light" />
      <View style={styles.header}>
        <View style={styles.iconButton}>
          <Feather name="chevron-left" size={22} color="#fff" />
        </View>
        <Text style={styles.headerTitle}>New note</Text>
        <View style={styles.iconButton}>
          <Feather name="more-horizontal" size={22} color="#fff" />
        </View>
      </View>

      <View style={[styles.toast, !saved && styles.toastHidden]}>
        <Feather name="check-circle" size={18} color={ACCENT} />
        <Text style={styles.toastText}>Saved: {saved ?? ''}</Text>
      </View>
      <Animated.View style={{ opacity: enter }}>
        <Text style={styles.section}>Recent</Text>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.recentRow}>
          {RECENT.map((r) => (
            <View key={r.title} style={styles.card}>
              <View style={[styles.dot, { backgroundColor: r.color }]} />
              <Text style={styles.cardTitle} numberOfLines={2}>{r.title}</Text>
              <Text style={styles.cardMeta}>{r.tag} · {r.time}</Text>
            </View>
          ))}
        </ScrollView>

        <TextInput
          style={styles.input}
          placeholder="Title"
          placeholderTextColor="#6B6B80"
          value={title}
          onChangeText={setTitle}
        />
        <TextInput
          style={[styles.input, styles.bodyInput]}
          placeholder="Start writing..."
          placeholderTextColor="#6B6B80"
          value={body}
          onChangeText={setBody}
          multiline
          textAlignVertical="top"
        />

        <Text style={styles.section}>Tag</Text>
        <View style={styles.tagRow}>
          {TAGS.map((t) => {
            const on = t.name === tag;
            return (
              <TouchableOpacity
                key={t.name}
                onPress={() => setTag(t.name)}
                style={[styles.chip, on && { backgroundColor: t.color, borderColor: t.color }]}
              >
                <Text style={[styles.chipText, on && { color: '#0B0B12' }]}>{t.name}</Text>
              </TouchableOpacity>
            );
          })}
        </View>


        <TouchableOpacity activeOpacity={0.85} onPress={save} style={styles.saveWrap}>
          <LinearGradient colors={[ACCENT, '#8EF06A']} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={styles.save}>
            <Feather name="check" size={20} color="#0B0B12" />
            <Text style={styles.saveText}>Save note</Text>
          </LinearGradient>
        </TouchableOpacity>
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#0B0B12', paddingHorizontal: 20, paddingTop: 56 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 18 },
  headerTitle: { fontFamily: 'SpaceGrotesk_700Bold', fontSize: 22, color: '#fff' },
  iconButton: { width: 42, height: 42, borderRadius: 21, backgroundColor: '#1B1B27', alignItems: 'center', justifyContent: 'center' },
  section: { fontFamily: 'SpaceGrotesk_500Medium', fontSize: 14, color: '#9A9AB0', marginBottom: 10, letterSpacing: 0.6 },
  recentRow: { paddingBottom: 18, gap: 12 },
  card: {
    width: 150, height: 104, borderRadius: 18, padding: 14, backgroundColor: '#171722',
    borderWidth: 1, borderColor: '#262636', justifyContent: 'space-between',
    shadowColor: '#000', shadowOpacity: 0.4, shadowRadius: 10, shadowOffset: { width: 0, height: 6 }, elevation: 6,
  },
  dot: { width: 10, height: 10, borderRadius: 5 },
  cardTitle: { fontFamily: 'SpaceGrotesk_700Bold', fontSize: 15, color: '#fff' },
  cardMeta: { fontFamily: 'SpaceGrotesk_400Regular', fontSize: 12, color: '#9A9AB0' },
  input: {
    backgroundColor: '#171722', borderWidth: 1, borderColor: '#262636', borderRadius: 16, paddingHorizontal: 16,
    fontFamily: 'SpaceGrotesk_500Medium', fontSize: 17, color: '#fff', height: 56, marginBottom: 14,
  },
  bodyInput: { height: 130, paddingTop: 14 },
  tagRow: { flexDirection: 'row', gap: 10, marginBottom: 20 },
  chip: { paddingHorizontal: 18, paddingVertical: 10, borderRadius: 999, borderWidth: 1, borderColor: '#33334A' },
  chipText: { fontFamily: 'SpaceGrotesk_500Medium', fontSize: 15, color: '#D4D4E4' },
  toast: { flexDirection: 'row', alignItems: 'center', gap: 8, height: 24, marginBottom: 10 },
  toastHidden: { opacity: 0 },
  toastText: { fontFamily: 'SpaceGrotesk_500Medium', fontSize: 15, color: ACCENT },
  saveWrap: { marginTop: 4 },
  save: { height: 60, borderRadius: 18, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 10 },
  saveText: { fontFamily: 'SpaceGrotesk_700Bold', fontSize: 18, color: '#0B0B12' },
});
