import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/ui.dart';

/// Paso 4 — minimarket de la estación seleccionada.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  ProductCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final items = s.productsIn(_filter);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            OHeader(
              title: 'Minimarket',
              step: s.station?.name ?? 'Estación',
              subtitle: 'Opcional — puedes ir directo al combustible.',
              onBack: () => Navigator.pop(context),
              action: IconButton(
                onPressed: () => Navigator.pushNamed(context, Routes.voice),
                icon: const Icon(Icons.mic_none, color: C.amber),
              ),
            ),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _chip('Todo', _filter == null, () => setState(() => _filter = null)),
                  ...ProductCategory.values.map((c) =>
                      _chip(c.label, _filter == c, () => setState(() => _filter = c))),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.86,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) => _productCard(s, items[i]),
              ),
            ),
            _footer(context, s),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: sel ? C.green : C.surface,
              borderRadius: Radii.pill,
              border: Border.all(color: sel ? C.green : C.line),
            ),
            child: Text(
              label,
              style: body(
                size: 13,
                weight: FontWeight.w600,
                color: sel ? const Color(0xFF0C130F) : C.muted,
              ),
            ),
          ),
        ),
      );

  Widget _productCard(AppState s, Product p) {
    final qty = s.qtyOf(p);
    return OCard(
      padding: const EdgeInsets.all(14),
      accent: qty > 0 ? C.green : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OThumb(seed: p.name, tint: p.inStock ? C.green : C.mutedDim),
              if (!p.inStock) OPill('AGOTADO', color: C.mutedDim),
            ],
          ),
          const Spacer(),
          Text(p.name, style: body(size: 14, weight: FontWeight.w600, height: 1.25)),
          Gap.h4,
          Text(p.detail, style: body(size: 11, color: C.mutedDim)),
          Gap.h12,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('\$${p.price.toStringAsFixed(2)}',
                  style: mono(size: 15, color: C.bone, weight: FontWeight.w600)),
              if (!p.inStock)
                const SizedBox.shrink()
              else if (qty == 0)
                _round(Icons.add, () => s.add(p), C.green)
              else
                Row(
                  children: [
                    _round(Icons.remove, () => s.remove(p), C.mutedDim, small: true),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('$qty', style: mono(size: 14, color: C.bone)),
                    ),
                    _round(Icons.add, () => s.add(p), C.green, small: true),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _round(IconData icon, VoidCallback onTap, Color color, {bool small = false}) => InkWell(
        onTap: onTap,
        borderRadius: Radii.pill,
        child: Container(
          width: small ? 26 : 32,
          height: small ? 26 : 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: Radii.pill,
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Icon(icon, size: small ? 14 : 18, color: color),
        ),
      );

  Widget _footer(BuildContext context, AppState s) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        decoration: const BoxDecoration(
          color: C.inkDeep,
          border: Border(top: BorderSide(color: C.line)),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OLabel('${s.cartCount} artículo(s)'),
                Gap.h4,
                Text('\$${s.itemsTotal.toStringAsFixed(2)}',
                    style: mono(size: 20, color: C.bone, weight: FontWeight.w600)),
              ],
            ),
            Gap.w16,
            Expanded(
              child: OButton(
                label: 'Combustible',
                trailing: '→',
                onTap: () => Navigator.pushNamed(context, Routes.fuel),
              ),
            ),
          ],
        ),
      );
}
