import 'package:flutter/material.dart';

class SearchCustomerScreen extends StatelessWidget {
  const SearchCustomerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Client')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Search for a client by name or phone',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Search field
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search Client',
                suffixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 24),

            // List of search results (currently empty)
            Expanded(
              child: ListView.builder(
                itemCount: 0, // This should be updated to show actual clients
                itemBuilder: (context, index) {
                  return ListTile(
                    title: const Text('Client Name'),
                    subtitle: const Text('Phone: 123456789'),
                    onTap: () {
                      // Logic to view selected client details goes here
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
