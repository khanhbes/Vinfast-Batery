import { initializeApp } from 'firebase/app'
import { getAuth } from 'firebase/auth'
import { getFirestore } from 'firebase/firestore'

const firebaseConfig = {
  apiKey: 'AIzaSyAKoNr2iPZi2XB0l_JaGhTkM2hsitwqyKE',
  authDomain: 'vinfast-873db.firebaseapp.com',
  projectId: 'vinfast-873db',
  storageBucket: 'vinfast-873db.firebasestorage.app',
  messagingSenderId: '450938791386',
  appId: '1:450938791386:android:fde2bf0210038fa32dcce3',
}

const app = initializeApp(firebaseConfig)
export const auth = getAuth(app)
export const db = getFirestore(app)
export default app
