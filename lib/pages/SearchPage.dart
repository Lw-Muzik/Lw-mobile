import 'package:eq_app/Routes/routes.dart';
import 'package:flutter/material.dart';

class SearchPage extends SearchDelegate {
  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        onPressed: () {},
        icon: const Icon(Icons.close),
      )
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return InkWell(
      child: const Icon(Icons.arrow_back_ios_new),
      onTap: () => Routes.pop(context),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return ListView(
      children: [],
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return ListView();
  }
}
