import '../../features/auth/models/auth_user.dart';
import '../../features/clients/models/client.dart';
import '../../features/products/models/product.dart';
import '../models/country.dart';
import 'api_client.dart';

class CatalogService {
  CatalogService(this.api);

  final ApiClient api;

  Future<List<Product>> products() async {
    final data = await api.getList('/products/');
    return data
        .map((item) => Product.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProduct(Map<String, dynamic> data, {int? id}) async {
    if (id == null) {
      await api.post('/products/', data);
    } else {
      await api.put('/products/$id/', data);
    }
  }

  Future<void> deleteProduct(int id) => api.delete('/products/$id/');

  Future<List<Country>> countries() async {
    final data = await api.getList('/countries/');
    return data
        .map((item) => Country.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Client>> clients() async {
    final data = await api.getList('/clients/');
    return data
        .map((item) => Client.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveClient(Map<String, dynamic> data, {int? id}) async {
    if (id == null) {
      await api.post('/clients/', data);
    } else {
      await api.put('/clients/$id/', data);
    }
  }

  Future<void> deleteClient(int id) => api.delete('/clients/$id/');

  Future<List<AuthUser>> users() async {
    final data = await api.getList('/users/');
    return data
        .map((item) => AuthUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveUser(Map<String, dynamic> data, {int? id}) async {
    if (id == null) {
      await api.post('/users/', data);
    } else {
      await api.put('/users/$id/', data);
    }
  }

  Future<void> deactivateUser(int id) => api.delete('/users/$id/');
}
