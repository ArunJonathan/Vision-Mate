const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

async function getTokensForUserIds(uids) {
  if (!uids || uids.length === 0) return [];
  try {
    const snaps = await Promise.all(
      uids.map((uid) => db.collection("users").doc(uid).get())
    );
    return snaps
      .map((d) => (d.exists && d.data()?.fcmToken ? d.data().fcmToken : null))
      .filter((t) => !!t);
  } catch (e) {
    console.error("Error in getTokensForUserIds:", e.stack);
    return [];
  }
}

exports.sendSOSNotification = onDocumentCreated("sos_requests/{sosId}", async (event) => {
  try {
    const sos = event.data.data();
    if (!sos || sos.status !== "pending") return;

    const seekerUid = sos.uid;
    if (!seekerUid) return;

    const seekerDoc = await db.collection("users").doc(seekerUid).get();
    if (!seekerDoc.exists) return;

    const s = seekerDoc.data() || {};
    const seekerName = s.displayName || s.email || "Someone";
    const helperIds = Array.isArray(s.helpers) ? s.helpers : [];
    if (helperIds.length === 0) return;

    const tokens = await getTokensForUserIds(helperIds);
    if (tokens.length === 0) return;

    const isVoiceCommand = sos.isVoiceCommand || false;
    const batteryInfo = Number.isFinite(sos.battery) ? ` Battery: ${sos.battery}%` : "";
    const locationString = JSON.stringify(sos.location || {});
    
    const payload = {
      notification: {
        title: `🆘 SOS ALERT - ${isVoiceCommand ? "VOICE" : "EMERGENCY"}`,
        body: `${seekerName} needs help!${batteryInfo}`,
      },
      data: {
        type: "sos_created",
        sosId: event.params.sosId,
        seekerUid,
        seekerName,
        location: locationString,
        isVoiceCommand: isVoiceCommand.toString(),
      },
      android: {
        priority: "high",
        notification: {
          sound: "sos_alert.mp3",
          defaultSound: false,
          channelId: "sos_emergency_final",
          priority: "max",
          visibility: "public",
          defaultVibrateTimings: false,
          vibrateTimingsMillis: [0, 1000, 500, 1000, 500, 1000],
          color: "#FF0000",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "sos_alert.caf",
            badge: 1,
            alert: {
              title: `🆘 SOS ALERT - ${isVoiceCommand ? "VOICE" : "EMERGENCY"}`,
              body: `${seekerName} needs help!${batteryInfo}`,
            },
          },
        },
      },
    };

    await admin.messaging().sendEachForMulticast({
      tokens: tokens,
      ...payload,
    });

    console.log("✅ Sent SOS notification to helpers for SOS ID:", event.params.sosId);
  } catch (e) {
    console.error("Error in sendSOSNotification:", e.stack);
  }
});

exports.notifyOnAcceptance = onDocumentWritten("sos_requests/{sosId}", async (event) => {
  try {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};

    if (before.status === after.status || after.status !== "accepted") return;

    const seekerUid = after.uid;
    if (!seekerUid) return;

    const seekerDoc = await db.collection("users").doc(seekerUid).get();
    if (!seekerDoc.exists) return;

    const s = seekerDoc.data() || {};
    const helperIds = Array.isArray(s.helpers) ? s.helpers : [];
    if (helperIds.length === 0) return;

    const acceptingId = after.helperId;
    const acceptingName = after.helperName || "A helper";

    const otherHelperIds = helperIds.filter((id) => id !== acceptingId);
    const otherTokens = await getTokensForUserIds(otherHelperIds);
    if (otherTokens.length > 0) {
      const locationString = JSON.stringify(after.location || {});
      const payload = {
        notification: {
          title: "SOS Accepted",
          body: `${acceptingName} accepted the request. You're now in monitoring mode.`,
        },
        data: {
          type: "sos_accepted",
          sosId: event.params.sosId,
          seekerUid,
          location: locationString,
        },
      };
      await admin.messaging().sendToDevice(otherTokens, payload);
      console.log("✅ Notified other helpers for SOS ID:", event.params.sosId);
    }
  } catch (e) {
    console.error("Error in notifyOnAcceptance:", e.stack);
  }
});

exports.notifyBatteryLow = onDocumentWritten("sos_requests/{sosId}", async (event) => {
  try {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};

    if (before.batteryLow === true || after.batteryLow !== true || after.battery >= 20) return;

    const seekerUid = after.uid;
    if (!seekerUid) return;

    const acceptingId = after.helperId;
    if (!acceptingId) return;

    const tokens = await getTokensForUserIds([acceptingId]);
    if (tokens.length === 0) return;

    const seekerDoc = await db.collection("users").doc(seekerUid).get();
    const seekerName = seekerDoc.data()?.displayName || seekerDoc.data()?.email || "The seeker";

    const locationString = JSON.stringify(after.location || {});
    const payload = {
      notification: {
        title: "⚠️ Low Battery",
        body: `${seekerName}'s battery is below 20%. Reach them ASAP.`,
      },
      data: {
        type: "battery_low",
        sosId: event.params.sosId,
        seekerUid,
        location: locationString,
      },
    };

    await admin.messaging().sendToDevice(tokens, payload);
    console.log("✅ Sent low-battery alert for SOS ID:", event.params.sosId);
  } catch (e) {
    console.error("Error in notifyOnBatteryLow:", e.stack);
  }
});

exports.linkHelperWithCode = onCall(async (request) => {
  const { inviteCode } = request.data;
  const helperUid = request.auth?.uid;

  console.log("Linking attempt by helper UID:", helperUid, "with invite code:", inviteCode, "at", new Date().toISOString());

  if (!helperUid) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }
  if (!inviteCode || !/^[A-Z0-9]{6}$/.test(inviteCode)) {
    throw new HttpsError("invalid-argument", "Invalid invite code format. Use 6 alphanumeric characters.");
  }

  try {
    const helperDoc = await db.collection("users").doc(helperUid).get();
    if (!helperDoc.exists) {
      throw new HttpsError("not-found", "Helper profile does not exist.");
    }

    const seekers = await db.collection("users")
      .where("role", "==", "seeker")
      .where("inviteCode", "==", inviteCode)
      .limit(1)
      .get();

    console.log("Seeker query result count:", seekers.size, "at", new Date().toISOString());

    if (seekers.empty) {
      throw new HttpsError("not-found", "Invalid or expired invite code.");
    }

    const seekerUid = seekers.docs[0].id;
    const seekerData = seekers.docs[0].data();
    console.log("Found seeker UID:", seekerUid, "with data:", JSON.stringify(seekerData, null, 2));

    const helperData = helperDoc.data();
    if (helperData?.linkedSeeker && helperData.linkedSeeker !== seekerUid) {
      throw new HttpsError("already-exists", "Helper is already linked to another seeker.");
    }

    await db.runTransaction(async (tx) => {
      const seekerRef = db.collection("users").doc(seekerUid);
      const helperRef = db.collection("users").doc(helperUid);

      const [helperDocTx, seekerDocTx] = await tx.getAll(helperRef, seekerRef);
      
      if (!seekerDocTx.exists) {
        throw new HttpsError("not-found", "Seeker document does not exist.");
      }

      const seekerDataTx = seekerDocTx.data() || {};
      const helpersArray = Array.isArray(seekerDataTx.helpers) ? seekerDataTx.helpers : [];
      
      if (!helpersArray.includes(helperUid)) {
        tx.update(seekerRef, {
          helpers: admin.firestore.FieldValue.arrayUnion(helperUid),
        });
        console.log("Updated seeker", seekerUid, "helpers array with helper", helperUid);
      } else {
        console.log("Helper", helperUid, "already in seeker", seekerUid, "helpers array");
      }

      tx.set(helperRef, { linkedSeeker: seekerUid }, { merge: true });
      console.log("Updated helper", helperUid, "with linkedSeeker", seekerUid);
    });

    const [updatedSeekerDoc, updatedHelperDoc] = await Promise.all([
      db.collection("users").doc(seekerUid).get(),
      db.collection("users").doc(helperUid).get(),
    ]);
    console.log("Post-transaction: Seeker helpers array:", updatedSeekerDoc.data()?.helpers);
    console.log("Post-transaction: Helper linkedSeeker:", updatedHelperDoc.data()?.linkedSeeker);

    return { success: true, seekerUid };
  } catch (e) {
    console.error("Linking transaction failed:", e.message, e.stack);
    
    if (e instanceof HttpsError) {
      throw e;
    }
    
    throw new HttpsError("internal", `Linking failed: ${e.message}`);
  }
});