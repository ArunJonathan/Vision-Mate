import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userUid = FirebaseAuth.instance.currentUser?.uid;
    if (userUid == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS History', style: TextStyle(color: Colors.white)),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Simplified query - only filter by uid, then filter status in code
        stream: FirebaseFirestore.instance.collection('sos_requests')
            .where('uid', isEqualTo: userUid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.teal));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No requests found.'));
          }

          // Filter completed requests in code and sort by date
          List<QueryDocumentSnapshot> completedRequests = snapshot.data!.docs
              .where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                return data['status'] == 'completed';
              })
              .toList();

          // Sort by completedAt date (newest first)
          completedRequests.sort((a, b) {
            var dataA = a.data() as Map<String, dynamic>;
            var dataB = b.data() as Map<String, dynamic>;
            Timestamp? timeA = dataA['completedAt'];
            Timestamp? timeB = dataB['completedAt'];
            
            if (timeA == null && timeB == null) return 0;
            if (timeA == null) return 1;
            if (timeB == null) return -1;
            
            return timeB.compareTo(timeA); // Descending order (newest first)
          });

          if (completedRequests.isEmpty) {
            return const Center(child: Text('No completed requests.'));
          }

          return ListView.builder(
            itemCount: completedRequests.length,
            itemBuilder: (context, index) {
              var doc = completedRequests[index];
              var data = doc.data() as Map<String, dynamic>;
              
              // Format the date nicely
              String formattedDate = 'N/A';
              if (data['completedAt'] != null) {
                DateTime dateTime = (data['completedAt'] as Timestamp).toDate();
                formattedDate = '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
              }

              return Card(
                margin: const EdgeInsets.all(8.0),
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text('SOS Request Completed'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Helper: ${data['helperName'] ?? 'Unknown'}'),
                      Text('Completed: $formattedDate'),
                      if (data['battery'] != null) 
                        Text('Battery at completion: ${data['battery']}%'),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}