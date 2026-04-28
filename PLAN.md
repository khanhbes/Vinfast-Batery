Act as an expert mobile app developer. I need to implement a series of new features, UI/UX improvements, and bug fixes for my electric vehicle/battery management application. 

Please review the following requirements and provide the necessary code updates, architecture suggestions, and implementation steps:

### 1. UI/UX: Sticky Header
- Implement a sticky/frozen header for the "Vinfast Battery" title and the notification bell icon so they remain fixed at the top of the screen when the user scrolls. 
- Clean up the UI by removing any old or duplicate notification icons and legacy "Vinfast Battery" text.

### 2. AI Battery Prediction Tab (Fine-Tuning Workflow)
- Enhance the "AI pin" tab to allow users to interact with and provide feedback to the charging prediction model.
- **Workflow:** The user inputs their current battery level (e.g., 20% at 2:00 PM) and their target percentage (e.g., 80%). The model predicts the charging time (e.g., 4 hours) and calculates the completion time (6:00 PM).
- **Reminders:** Set a system reminder/alarm for the user to unplug at the predicted time.
- **Data Collection:** After the charging session, prompt the user to input the *actual* final battery percentage. Save this real-world data log into a local CSV file so it can be used to fine-tune the model later.

### 3. Authentication & Registration
- **Persistent Login:** Implement local storage for session management so the user stays logged in across app restarts.
- **Registration Page:** Build a professional, polished sign-up screen capturing: Full Name, Email (to be used as the username), Phone Number, and Password.
- Route this saved data to a new "Personal Information" section within the app for the user to view/manage.

### 4. Settings Tab Refactoring
- Fully develop and flesh out the "Settings" screen. 
- Clean up the codebase by completely removing any redundant, unused, or legacy features from the previous version.

### 5. Vehicle Garage (Within Settings)
- Create a comprehensive "Add Vehicle" feature inside the "Vehicle Garage" menu.
- **Database/Selection:** Allow users to select from a comprehensive list of electric motorcycles on the market (filtering by Brand, Model, Release Year, Manufacturer).
- **Specs Display:** Once a vehicle is selected, display a professional, detailed spec sheet (Name, Color, Battery specs, Motor power, etc.).
- **Editable Specs:** Add an "Edit" function so the user can manually correct or update the vehicle's specifications if the default database info is inaccurate.

### 6. Dynamic AI Model Updates
- Implement a background or on-launch sync mechanism. When a new prediction model is deployed on the server, the app should automatically fetch and update the model used in the AI tab without requiring a full app store update.

### 7. Application Settings Implementation
- Fully develop the following toggles/menus in Application Settings:
  - Notifications (General)
  - Theme Toggle (Light/Dark mode)
  - Push Notifications
  - Biometric Authentication (FaceID/Fingerprint)
  - Help
  - About
- **Fallback:** If any of these specific features cannot be fully implemented yet, ensure tapping them triggers an "Under Development" (Coming Soon) snackbar/toast rather than a dead tap.

### 8. App Version Synchronization
- Fix the versioning display. The app is currently incorrectly showing "V2.4.1". 
- Ensure the UI dynamically fetches and displays the actual build version from the app's package information (e.g., via `package_info_plus` if using Flutter) rather than using a hardcoded string.